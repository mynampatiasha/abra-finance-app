const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');

// ============================================================================
// MONGOOSE SCHEMA DEFINITION
// ============================================================================
const proofFileSchema = new mongoose.Schema({
  filename: String,
  originalName: String,
  path: String,
  size: Number,
  mimetype: String
}, { _id: false });

const digitalExpenseSchema = new mongoose.Schema({
  voucherNumber: { type: String, required: true },
  date: { type: String, required: true },
  amount: { type: Number, required: true },
  paymentMethod: { type: String, default: null },
  amountPaidTo: { type: String, default: null },
  amountInWords: { type: String, default: null },
  onAccountOf: { type: String, default: null },
  expenseCategory: { type: String, required: true },
  receivedBy: { type: String, default: null },
  proofFile: proofFileSchema,
  proofFiles: [proofFileSchema],
  status: {
    type: String,
    enum: ['Pending', 'Approved', 'Declined'],
    default: 'Pending'
  },
  managerReason: { type: String, default: null },
  approvedAt: { type: Date, default: null },
  addedBy: { type: String, default: null },
  orgId: { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null },
}, {
  timestamps: true
});

const DigitalExpense = mongoose.models.DigitalExpense || mongoose.model('DigitalExpense', digitalExpenseSchema);

const digitalExpenseCategorySchema = new mongoose.Schema({
  categoryName: { type: String, required: true },
  orgId: { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null }
}, { timestamps: true });

const DigitalExpenseCategory = mongoose.models.DigitalExpenseCategory || mongoose.model('DigitalExpenseCategory', digitalExpenseCategorySchema);

const digitalExpenseHistorySchema = new mongoose.Schema({
  action: { type: String, required: true },
  voucherNumber: { type: String, default: null },
  details: { type: String, required: true },
  performedBy: { type: String, required: true },
  userId: { type: String, default: null },
  orgId: { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null }
}, { timestamps: true });

const DigitalExpenseHistory = mongoose.models.DigitalExpenseHistory || mongoose.model('DigitalExpenseHistory', digitalExpenseHistorySchema);

async function logHistory(req, action, voucherNumber, details) {
  try {
    const orgId = req.user?.orgId || null;
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const performedBy = req.user?.email || req.user?.name || 'System';
    const userId = req.user?.userId || req.user?._id || null;
    await DigitalExpenseHistory.create({ action, voucherNumber, details, performedBy, userId, orgId, branchId });
  } catch (error) {
    console.error('Failed to log history:', error);
  }
}
// ============================================================================
// MULTER CONFIGURATION - FILE UPLOADS
// ============================================================================
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = './uploads/digital_expenses';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, 'd-exp-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const fileFilter = (req, file, cb) => {
  const allowedTypes = /jpeg|jpg|png|pdf|gif|webp/;
  const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
  const mimetype = allowedTypes.test(file.mimetype) || file.mimetype === 'application/octet-stream';

  if (mimetype && extname) {
    return cb(null, true);
  } else {
    cb(new Error('Only images and PDF files are allowed!'));
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: { fileSize: 10 * 1024 * 1024 } // 10MB
});

function handleError(res, statusCode, message, error = null) {
  console.error(`❌ ${message}:`, error);
  res.status(statusCode).json({
    success: false,
    message,
    error: error?.message || error
  });
}

// ============================================================================
// GET DIGITAL EXPENSE CATEGORIES
// ============================================================================
router.get('/categories', async (req, res) => {
  try {
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    Object.assign(query, req.branchFilter || {});

    const cats = await DigitalExpenseCategory.find(query).sort({ categoryName: 1 });
    res.json({ success: true, data: cats.map(c => c.categoryName) });
  } catch (error) {
    handleError(res, 500, 'Error fetching categories', error);
  }
});

// ============================================================================
// ADD DIGITAL EXPENSE CATEGORY
// ============================================================================
router.post('/categories', async (req, res) => {
  try {
    const { categoryName } = req.body;
    if (!categoryName) return res.status(400).json({ success: false, message: 'Category Name is required' });

    const orgId = req.user?.orgId || null;
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;

    // Check if exists
    const exists = await DigitalExpenseCategory.findOne({ categoryName, orgId, branchId });
    if (exists) {
      return res.json({ success: true, message: 'Category already exists' });
    }

    const newCat = new DigitalExpenseCategory({ categoryName, orgId, branchId });
    await newCat.save();
    res.json({ success: true, message: 'Category added', data: newCat });
  } catch (error) {
    handleError(res, 500, 'Error adding category', error);
  }
});

// ============================================================================
// GET ALL DIGITAL EXPENSES (BRANCH-WISE FILTERING)
// ============================================================================
router.get('/', async (req, res) => {
  try {
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    Object.assign(query, req.branchFilter || {});

    // Optional filters from frontend
    if (req.query.status) query.status = req.query.status;

    const expenses = await DigitalExpense.find(query).sort({ createdAt: -1 });
    require('fs').writeFileSync('./debug_get_route.json', JSON.stringify({ count: expenses.length, query: query, expenses: expenses }, null, 2));
    res.json({
      success: true,
      data: expenses,
      total: expenses.length
    });
  } catch (error) {
    handleError(res, 500, 'Error fetching digital expenses', error);
  }
});

// ============================================================================
// CREATE NEW DIGITAL EXPENSE (ACCOUNTANT)
// ============================================================================
router.post('/', upload.array('proofFiles', 5), async (req, res) => {
  try {
    const {
      date, amount, paymentMethod, amountPaidTo, amountInWords, onAccountOf, expenseCategory, receivedBy
    } = req.body;

    const errors = [];
    if (!date) errors.push('Date is required');
    if (!expenseCategory) errors.push('Expense Category is required');
    if (!amount || isNaN(parseFloat(amount))) errors.push('Valid Amount is required');

    if (errors.length > 0) {
      if (req.files && req.files.length > 0) {
        req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
      }
      return res.status(400).json({ success: false, message: 'Validation failed', errors });
    }

    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const count = await DigitalExpense.countDocuments({ branchId });
    const voucherNumber = `DE${String(count + 1).padStart(4, '0')}`;

    const newExpense = new DigitalExpense({
      voucherNumber,
      date,
      amount: parseFloat(amount),
      paymentMethod,
      amountPaidTo,
      amountInWords,
      onAccountOf,
      expenseCategory,
      receivedBy,
      status: 'Pending',
      addedBy: req.user?.email || 'System',
      orgId: req.user?.orgId || null,
      branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
      proofFiles: req.files ? req.files.map(f => ({
        filename: f.filename,
        originalName: f.originalname,
        path: f.path,
        size: f.size,
        mimetype: f.mimetype
      })) : []
    });

    await newExpense.save();
    await logHistory(req, 'Created', voucherNumber, `Created expense voucher for ₹${amount} (${expenseCategory})`);
    res.json({ success: true, message: 'Digital expense submitted successfully', data: newExpense });
  } catch (error) {
    if (req.files && req.files.length > 0) {
      req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
    }
    handleError(res, 500, 'Error creating digital expense', error);
  }
});

// ============================================================================
// EDIT DIGITAL EXPENSE (BRANCH OWNER / ADMIN)
// ============================================================================
router.put('/:id', upload.array('proofFiles', 5), async (req, res) => {
  try {
    const { id } = req.params;
    const {
      date, amount, paymentMethod, amountPaidTo, amountInWords, onAccountOf, expenseCategory, receivedBy, status
    } = req.body;

    const expense = await DigitalExpense.findById(id);
    if (!expense) {
      if (req.files && req.files.length > 0) {
        req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
      }
      return res.status(404).json({ success: false, message: 'Expense not found' });
    }

    // Branch authorization check
    if (req.user?.orgId && expense.orgId !== req.user.orgId) {
      if (req.files && req.files.length > 0) {
        req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
      }
      return res.status(403).json({ success: false, message: 'Unauthorized access to expense' });
    }

    if (date) expense.date = date;
    if (amount) expense.amount = parseFloat(amount);
    if (paymentMethod) expense.paymentMethod = paymentMethod;
    if (amountPaidTo) expense.amountPaidTo = amountPaidTo;
    if (amountInWords) expense.amountInWords = amountInWords;
    if (onAccountOf) expense.onAccountOf = onAccountOf;
    if (expenseCategory) expense.expenseCategory = expenseCategory;
    if (receivedBy) expense.receivedBy = receivedBy;

    // Status can be updated during edit if provided
    if (status) {
      expense.status = status;
      if (status === 'Approved' || status === 'Pending') {
        expense.managerReason = null;
      }
    }

    if (req.files && req.files.length > 0) {
      // Remove old files if they exist
      if (expense.proofFiles && expense.proofFiles.length > 0) {
        expense.proofFiles.forEach(pf => {
          if (pf.path && fs.existsSync(pf.path)) fs.unlinkSync(pf.path);
        });
      }
      expense.proofFiles = req.files.map(f => ({
        filename: f.filename,
        originalName: f.originalname,
        path: f.path,
        size: f.size,
        mimetype: f.mimetype
      }));
    }

    await expense.save();
    await logHistory(req, 'Updated', expense.voucherNumber, `Updated expense details`);
    res.json({ success: true, message: 'Digital expense updated successfully', data: expense });
  } catch (error) {
    if (req.files && req.files.length > 0) {
      req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
    }
    handleError(res, 500, 'Error updating digital expense', error);
  }
});

// ============================================================================
// REVIEW DIGITAL EXPENSE (APPROVE / DECLINE)
// ============================================================================
router.put('/:id/status', async (req, res) => {
  try {
    const { id } = req.params;
    const { status, reason } = req.body;

    if (!['Approved', 'Declined', 'Pending'].includes(status)) {
      return res.status(400).json({ success: false, message: 'Invalid status' });
    }

    if (status === 'Declined' && !reason) {
      return res.status(400).json({ success: false, message: 'Reason is required when declining' });
    }

    const expense = await DigitalExpense.findById(id);
    if (!expense) return res.status(404).json({ success: false, message: 'Expense not found' });

    // Branch authorization check
    if (req.user?.orgId && expense.orgId !== req.user.orgId) {
      return res.status(403).json({ success: false, message: 'Unauthorized access to expense' });
    }

    expense.status = status;
    expense.managerReason = status === 'Declined' ? reason : null;

    if (status === 'Approved') {
      expense.approvedAt = new Date();
    } else {
      expense.approvedAt = null;
    }

    await expense.save();
    await logHistory(req, status === 'Pending' ? 'Reverted' : status, expense.voucherNumber, `Changed status to ${status}`);
    res.json({ success: true, message: `Expense ${status.toLowerCase()} successfully`, data: expense });
  } catch (error) {
    handleError(res, 500, 'Error updating digital expense status', error);
  }
});

// ============================================================================
// DELETE DIGITAL EXPENSE
// ============================================================================
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const expense = await DigitalExpense.findById(id);
    if (!expense) return res.status(404).json({ success: false, message: 'Expense not found' });

    if (req.user?.orgId && expense.orgId !== req.user.orgId) {
      return res.status(403).json({ success: false, message: 'Unauthorized' });
    }

    if (expense.proofFile && expense.proofFile.path && fs.existsSync(expense.proofFile.path)) {
      fs.unlinkSync(expense.proofFile.path);
    }

    await DigitalExpense.findByIdAndDelete(id);
    await logHistory(req, 'Deleted', expense.voucherNumber, `Deleted expense voucher`);
    res.json({ success: true, message: 'Expense deleted successfully' });
  } catch (error) {
    handleError(res, 500, 'Error deleting digital expense', error);
  }
});

// ============================================================================
// BULK IMPORT DIGITAL EXPENSES
// ============================================================================
router.post('/bulk-import', async (req, res) => {
  try {
    const { expenses } = req.body;
    if (!expenses || !Array.isArray(expenses)) {
      return res.status(400).json({ success: false, message: 'Invalid data format. Expected array of expenses.' });
    }

    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    let currentCount = await DigitalExpense.countDocuments({ branchId });

    const newExpenses = [];
    for (const exp of expenses) {
      if (!exp.date || !exp.amount || !exp.expenseCategory) continue; // Skip invalid rows
      currentCount++;
      const voucherNumber = `DE${String(currentCount).padStart(4, '0')}`;
      newExpenses.push({
        voucherNumber,
        date: exp.date,
        amount: parseFloat(exp.amount),
        paymentMethod: exp.paymentMethod || null,
        amountPaidTo: exp.amountPaidTo || null,
        amountInWords: exp.amountInWords || null,
        onAccountOf: exp.onAccountOf || null,
        expenseCategory: exp.expenseCategory,
        receivedBy: exp.receivedBy || null,
        status: 'Pending',
        addedBy: req.user?.email || 'System',
        orgId: req.user?.orgId || null,
        branchId
      });
    }

    if (newExpenses.length > 0) {
      await DigitalExpense.insertMany(newExpenses);
      await logHistory(req, 'Bulk Imported', null, `Bulk imported ${newExpenses.length} expenses`);
    }

    res.json({ success: true, message: `${newExpenses.length} expenses imported successfully` });
  } catch (error) {
    handleError(res, 500, 'Error importing expenses', error);
  }
});

// ============================================================================
// LOG REPORT GENERATION
// ============================================================================
router.post('/log-report', async (req, res) => {
  try {
    await logHistory(req, 'Report Generated', null, 'Generated digital expenses report');
    res.json({ success: true, message: 'Report logged successfully' });
  } catch (error) {
    handleError(res, 500, 'Error logging report', error);
  }
});

// ============================================================================
// GET HISTORY
// ============================================================================
router.get('/history', async (req, res) => {
  try {
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    Object.assign(query, req.branchFilter || {});

    // For admin, do not filter, so they see all history.
    if (req.user && req.user.role !== 'admin' && req.user.role !== 'owner') {
      const userVouchers = await DigitalExpense.find({ addedBy: req.user.email }).select('voucherNumber');
      const vNumbers = userVouchers.map(v => v.voucherNumber).filter(Boolean);
      query.$or = [
        { performedBy: req.user.email },
        { voucherNumber: { $in: vNumbers } }
      ];
    }

    const history = await DigitalExpenseHistory.find(query).sort({ createdAt: -1 });
    res.json({ success: true, data: history });
  } catch (error) {
    handleError(res, 500, 'Error fetching history', error);
  }
});

// ============================================================================
// GENERATE PDF
// ============================================================================
router.get('/debug-dump', async (req, res) => {
  try {
    const expenses = await DigitalExpense.find({});
    res.json({ success: true, count: expenses.length, data: expenses });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/:id/pdf', async (req, res) => {
  try {
    const expense = await DigitalExpense.findById(req.params.id);
    if (!expense) return res.status(404).json({ success: false, error: 'Expense not found' });

    const pdfsDir = path.join(process.cwd(), 'uploads', 'digital_expenses_pdf');
    if (!fs.existsSync(pdfsDir)) fs.mkdirSync(pdfsDir, { recursive: true });

    const filename = `DE-${expense.voucherNumber}-${Date.now()}.pdf`;
    const filepath = path.join(pdfsDir, filename);

    const doc = new PDFDocument({ size: 'A4', margin: 40 });
    const stream = fs.createWriteStream(filepath);
    doc.pipe(stream);

    // --- Fetch org data to get digital signature and branch name ---
    const { getEffectiveOrgData } = require('./branches');
    let orgData = null;
    let effOrgId = expense.orgId;
    let effBranchId = expense.branchId;

    try {
      if (mongoose.connection.db) {
        // Recovery logic if orgId is missing
        if (!effOrgId && expense.addedBy) {
          console.log(`[PDF Gen] Missing orgId for ${expense.voucherNumber}, attempting recovery via user ${expense.addedBy}`);
          const user = await mongoose.connection.db.collection('billing_users').findOne({ email: expense.addedBy });
          if (user && user.organizations?.length > 0) {
            effOrgId = user.organizations[0].orgId;
            // Also try to recover branchId
            if (!effBranchId && user.organizations[0].allowedBranches?.length > 0) {
              effBranchId = user.organizations[0].allowedBranches[0];
            }
            console.log(`[PDF Gen] Recovered effOrgId: ${effOrgId}, effBranchId: ${effBranchId}`);
          }
        }

        if (effOrgId) {
          orgData = await getEffectiveOrgData(effOrgId, effBranchId, mongoose.connection.db);
          console.log(`[PDF Gen] Retrieved orgData: ${orgData ? 'YES' : 'NO'} for orgId: ${effOrgId}, branchId: ${effBranchId}`);
        }
      }
      require('fs').writeFileSync('./debug_vars.json', JSON.stringify({
        expenseOrgId: expense.orgId,
        effOrgId: effOrgId,
        expenseBranchId: expense.branchId,
        effBranchId: effBranchId,
        hasDb: !!mongoose.connection.db,
        orgData: orgData
      }, null, 2));
    } catch (e) {
      console.error("DEBUG ERROR: ", e);
      require('fs').writeFileSync('./debug_log.txt', e.toString());
    }
    const displayName = orgData?.orgName?.toUpperCase() || 'ABRA FINANCE';

    // Dark blue header bar
    doc.rect(40, 40, 515, 60).fill('#0f1e3d');
    doc.fillColor('#ffffff').fontSize(18).font('Helvetica-Bold')
      .text('PAYMENT VOUCHER', 40, 52, { width: 515, align: 'center' });
    doc.fontSize(12).font('Helvetica')
      .text(displayName, 40, 75, { width: 515, align: 'center' });

    let y = 140;
    const drawRow = (label, value) => {
      doc.fillColor('#444444').font('Helvetica-Bold').fontSize(11).text(label, 40, y);
      doc.fillColor('#111111').font('Helvetica').fontSize(11).text(value || '-', 180, y, { width: 375 });
      const height = doc.heightOfString(value || '-', { width: 375, font: 'Helvetica', fontSize: 11 });
      doc.moveTo(180, y + height + 2).lineTo(555, y + height + 2).lineWidth(0.5).strokeColor('#aaaaaa').dash(1, { space: 2 }).stroke().undash();
      y += height + 15;
    };

    drawRow('Voucher No:', expense.voucherNumber);
    drawRow('Date:', expense.date);
    drawRow('Amount:', `Rs. ${expense.amount}`);
    drawRow('Payment Method:', expense.paymentMethod);
    drawRow('Amount Paid To:', expense.amountPaidTo);
    drawRow('Amount in Words:', expense.amountInWords);
    drawRow('On Account Of:', expense.onAccountOf);
    drawRow('Received By:', expense.receivedBy);

    y += 40;
    const isApproved = (expense.status || '').toLowerCase() === 'approved';


    const sigRelPath = orgData?.digitalSignaturePath;
    let actualSigH = 0;
    let actualSigW = 0;
    let sigAbsPath = null;
    let hasSig = false;

    if (isApproved && sigRelPath) {
      try {
        sigAbsPath = path.join(process.cwd(), sigRelPath.replace(/^\//, ''));
        if (fs.existsSync(sigAbsPath)) {
          let imgW = 100, imgH = 100;
          try {
            const buf = fs.readFileSync(sigAbsPath);
            const ext = path.extname(sigAbsPath).toLowerCase();
            if (ext === '.png' && buf.length > 24) {
              imgW = buf.readUInt32BE(16);
              imgH = buf.readUInt32BE(20);
            } else if ((ext === '.jpg' || ext === '.jpeg') && buf.length > 4) {
              let i = 2;
              while (i < buf.length - 8) {
                if (buf[i] === 0xFF && buf[i + 1] >= 0xC0 && buf[i + 1] <= 0xC3) {
                  imgH = buf.readUInt16BE(i + 5);
                  imgW = buf.readUInt16BE(i + 7);
                  break;
                }
                i += 2 + buf.readUInt16BE(i + 2);
              }
            }
          } catch (_) { }
          const scale = Math.min(160 / imgW, 70 / imgH); // max width 160, max height 70
          actualSigW = Math.round(imgW * scale);
          actualSigH = Math.round(imgH * scale);
          hasSig = true;
          y += actualSigH; // Make extra room above the line for the signature
        }
      } catch (e) { }
    }
    // -----------------------------------------------

    // Signatures
    doc.moveTo(40, y).lineTo(200, y).lineWidth(1).strokeColor('#000000').stroke();
    doc.fillColor('#000000').font('Helvetica-Bold').fontSize(10).text('Prepared By', 40, y + 5, { width: 160, align: 'center' });
    let preparerName = 'Accountant';
    if (expense.addedBy) {
      preparerName = expense.addedBy.split('@')[0].replace(/[^a-zA-Z0-9]/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
    }
    doc.font('Helvetica').fontSize(9).text(preparerName, 40, y + 18, { width: 160, align: 'center' });

    if (hasSig) {
      const centeredX = 395 + (160 - actualSigW) / 2;
      doc.image(sigAbsPath, centeredX, y - actualSigH - 2, { width: actualSigW, height: actualSigH });
    }
    doc.moveTo(395, y).lineTo(555, y).lineWidth(1).strokeColor('#000000').stroke();
    doc.fillColor('#000000').font('Helvetica-Bold').fontSize(10).text('Manager Approval', 395, y + 5, { width: 160, align: 'center' });
    doc.fillColor(isApproved ? 'green' : 'orange').font('Helvetica').fontSize(9).text(isApproved ? 'Approved Digitally' : 'Pending Approval', 395, y + 18, { width: 160, align: 'center' });

    // Proofs
    const proofs = [...(expense.proofFiles || [])];
    if (expense.proofFile && !proofs.some(p => p.path === expense.proofFile.path)) {
      proofs.push(expense.proofFile);
    }

    const imgProofs = proofs.filter(p => p.filename && !p.filename.toLowerCase().endsWith('.pdf'));

    if (imgProofs.length > 0) {
      let imgY = y + 50;
      doc.fillColor('#0f1e3d').fontSize(14).font('Helvetica-Bold').text('Attached Proofs', 40, imgY);
      doc.moveTo(40, imgY + 20).lineTo(555, imgY + 20).lineWidth(1).strokeColor('#cccccc').stroke();

      imgY += 40;
      let imgX = 40;

      for (const proof of imgProofs) {
        if (imgY > 580) { doc.addPage(); imgY = 40; imgX = 40; }
        try {
          const absPath = path.join(process.cwd(), proof.path);
          if (fs.existsSync(absPath)) {
            doc.image(absPath, imgX, imgY, { fit: [250, 250], align: 'center' });

            if (imgX === 40) {
              imgX = 305;
            } else {
              imgX = 40;
              imgY += 270;
            }
          }
        } catch (e) {
          console.log("PDF img error", e);
        }
      }
    }

    doc.end();

    stream.on('finish', () => {
      res.json({
        success: true,
        pdfUrl: `/uploads/digital_expenses_pdf/${filename}`
      });
    });

    stream.on('error', (err) => {
      res.status(500).json({ success: false, error: err.message });
    });

  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
