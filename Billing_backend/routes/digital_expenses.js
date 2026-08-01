const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const PDFDocument = require('pdfkit');
const pool = require('../config/mysql');
// Keep mongoose ONLY for the PDF generation org data recovery (or remove if no longer needed)
const mongoose = require('mongoose');

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

// Helper to map snake_case row to camelCase for frontend compatibility
function mapExpenseRowToCamelCase(row) {
  let finalAddedByName = row.added_by_name;
  if (!finalAddedByName && row.added_by) {
    finalAddedByName = row.added_by.split('@')[0].replace(/[^a-zA-Z0-9]/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  }

  return {
    _id: row.id,
    id: row.id,
    voucherNumber: row.voucher_number,
    date: row.expense_date ? new Date(row.expense_date).toISOString().split('T')[0] : null,
    amount: parseFloat(row.amount),
    paymentMethod: row.payment_method,
    amountPaidTo: row.amount_paid_to,
    amountInWords: row.amount_in_words,
    onAccountOf: row.on_account_of,
    expenseCategory: row.expense_category,
    receivedBy: row.received_by,
    proofFiles: row.proof_files ? JSON.parse(row.proof_files) : [],
    rebuttalProofFiles: row.rebuttal_proof_files ? JSON.parse(row.rebuttal_proof_files) : [],
    employeeResponse: row.employee_response,
    employeeResponseAt: row.employee_response_at,
    status: row.status,
    managerReason: row.manager_reason,
    approvedAt: row.approved_at,
    addedBy: row.added_by,
    addedByName: finalAddedByName,
    orgId: row.orgId,
    branchId: row.branchId,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

async function logHistory(req, action, voucherNumber, details) {
  try {
    const orgId = req.user?.orgId || null;
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const performedBy = req.user?.email || req.user?.name || 'System';
    const userId = req.user?.userId || req.user?._id || null;

    const sql = `INSERT INTO finance_digital_expense_history 
      (action, voucher_number, details, performed_by, employee_id, orgId, branchId) 
      VALUES (?, ?, ?, ?, ?, ?, ?)`;
    await pool.query(sql, [action, voucherNumber, details, performedBy, userId, orgId, branchId]);
  } catch (error) {
    console.error('Failed to log history:', error);
  }
}

// ============================================================================
// GET DIGITAL EXPENSE CATEGORIES
// ============================================================================
router.get('/categories', async (req, res) => {
  try {
    let sql = `SELECT DISTINCT category_name FROM finance_digital_expense_categories WHERE 1=1`;
    const params = [];

    if (req.user?.orgId) {
      sql += ` AND orgId = ?`;
      params.push(req.user.orgId);
    }
    if (req.branchFilter && req.branchFilter.branchId) {
      sql += ` AND branchId = ?`;
      params.push(req.branchFilter.branchId);
    }

    sql += ` ORDER BY category_name ASC`;
    const [rows] = await pool.query(sql, params);
    res.json({ success: true, data: rows.map(r => r.category_name) });
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
    let sqlCheck = `SELECT id FROM finance_digital_expense_categories WHERE category_name = ?`;
    const checkParams = [categoryName];
    if (orgId) { sqlCheck += ` AND orgId = ?`; checkParams.push(orgId); }
    if (branchId) { sqlCheck += ` AND branchId = ?`; checkParams.push(branchId); }
    sqlCheck += ` LIMIT 1`;

    const [existing] = await pool.query(sqlCheck, checkParams);
    if (existing.length > 0) {
      return res.json({ success: true, message: 'Category already exists' });
    }

    const sqlInsert = `INSERT INTO finance_digital_expense_categories (category_name, added_by, orgId, branchId) VALUES (?, ?, ?, ?)`;
    const [result] = await pool.query(sqlInsert, [categoryName, req.user?.email || 'System', orgId, branchId]);

    res.json({ success: true, message: 'Category added', data: { id: result.insertId, categoryName, orgId, branchId } });
  } catch (error) {
    handleError(res, 500, 'Error adding category', error);
  }
});


// ============================================================================
// GET ALL DIGITAL EXPENSES (BRANCH-WISE FILTERING)
// ============================================================================
router.get('/', async (req, res) => {
  try {
    let sql = `SELECT * FROM finance_digital_expenses WHERE 1=1`;
    const params = [];

    if (req.user?.orgId) {
      sql += ` AND (orgId = ? OR orgId IS NULL OR orgId = '6a05b2c6aef99160d927b0bf' OR orgId = '69df6eecb73c1ec7596c07c1')`;
      params.push(req.user.orgId);
    }

    // Strict Branch Isolation mirroring invoice automation
    let branchFilterIds = [];
    if (req.query.branchIds && req.query.branchIds.trim() !== '' && req.query.branchIds.trim() !== 'ALL') {
      branchFilterIds = req.query.branchIds.split(',').map(s => s.trim()).filter(Boolean);
    } else if (req.branchFilter && typeof req.branchFilter.branchId === 'string') {
      branchFilterIds = [req.branchFilter.branchId];
    } else if (req.branchFilter && req.branchFilter.branchId && Array.isArray(req.branchFilter.branchId.$in)) {
      branchFilterIds = req.branchFilter.branchId.$in;
    }

    if (branchFilterIds.length > 0) {
      const placeholders = branchFilterIds.map(() => '?').join(',');
      sql += ` AND branchId IN (${placeholders})`;
      params.push(...branchFilterIds);
    }

    if (req.query.status) {
      sql += ` AND status = ?`;
      params.push(req.query.status);
    }

    sql += ` ORDER BY created_at DESC`;
    
    console.log('[DEBUG] Digital Expenses Query:', sql);
    console.log('[DEBUG] Params:', params);
    
    const [rows] = await pool.query(sql, params);

    const expenses = rows.map(mapExpenseRowToCamelCase);
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
    const orgId = req.user?.orgId || null;
    const addedBy = req.user?.email || 'System';

    // Get count for voucher number (per branch ideally, but we can do it per org for consistency)
    let sqlCount = `SELECT COUNT(*) as c FROM finance_digital_expenses`;
    let countParams = [];
    if (branchId) {
      sqlCount += ` WHERE branchId = ?`;
      countParams.push(branchId);
    }
    const [countResult] = await pool.query(sqlCount, countParams);
    const count = countResult[0].c;
    const voucherNumber = `DE${String(count + 1).padStart(4, '0')}`;

    const proofFiles = req.files ? req.files.map(f => ({
      filename: f.filename,
      originalName: f.originalname,
      path: 'uploads/digital_expenses/' + f.filename,
      size: f.size,
      mimetype: f.mimetype
    })) : [];

    const sqlInsert = `INSERT INTO finance_digital_expenses 
      (voucher_number, expense_date, amount, payment_method, amount_paid_to, amount_in_words, 
       on_account_of, expense_category, received_by, status, added_by, orgId, branchId, proof_files) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

    const insertParams = [
      voucherNumber, date, parseFloat(amount), paymentMethod, amountPaidTo, amountInWords,
      onAccountOf, expenseCategory, receivedBy, 'Pending', addedBy, orgId, branchId, JSON.stringify(proofFiles)
    ];

    const [result] = await pool.query(sqlInsert, insertParams);

    // Fetch the newly created row
    const [newRow] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [result.insertId]);

    await logHistory(req, 'Created', voucherNumber, `Created expense voucher for ₹${amount} (${expenseCategory})`);
    res.json({ success: true, message: 'Digital expense submitted successfully', data: mapExpenseRowToCamelCase(newRow[0]) });
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

    const [rows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    if (rows.length === 0) {
      if (req.files && req.files.length > 0) req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
      return res.status(404).json({ success: false, message: 'Expense not found' });
    }
    const expense = rows[0];

    if (req.user?.orgId && expense.orgId !== null && expense.orgId !== req.user.orgId && expense.orgId !== '6a05b2c6aef99160d927b0bf' && expense.orgId !== '69df6eecb73c1ec7596c07c1') {
      if (req.files && req.files.length > 0) req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
      return res.status(403).json({ success: false, message: 'Unauthorized access to expense' });
    }

    let updates = [];
    let params = [];

    if (date) { updates.push('expense_date = ?'); params.push(date); }
    if (amount) { updates.push('amount = ?'); params.push(parseFloat(amount)); }
    if (paymentMethod) { updates.push('payment_method = ?'); params.push(paymentMethod); }
    if (amountPaidTo) { updates.push('amount_paid_to = ?'); params.push(amountPaidTo); }
    if (amountInWords) { updates.push('amount_in_words = ?'); params.push(amountInWords); }
    if (onAccountOf) { updates.push('on_account_of = ?'); params.push(onAccountOf); }
    if (expenseCategory) { updates.push('expense_category = ?'); params.push(expenseCategory); }
    if (receivedBy) { updates.push('received_by = ?'); params.push(receivedBy); }

    if (status) {
      updates.push('status = ?'); params.push(status);
      if (status === 'Approved' || status === 'Pending') {
        updates.push('manager_reason = NULL');
      }
    }

    if (req.files && req.files.length > 0) {
      if (expense.proof_files) {
        const oldFiles = JSON.parse(expense.proof_files);
        oldFiles.forEach(pf => {
          const absPath = path.join(process.cwd(), pf.path || ('uploads/digital_expenses/' + pf.filename));
          if (fs.existsSync(absPath)) fs.unlinkSync(absPath);
        });
      }
      const newFiles = req.files.map(f => ({
        filename: f.filename,
        originalName: f.originalname,
        path: 'uploads/digital_expenses/' + f.filename,
        size: f.size,
        mimetype: f.mimetype
      }));
      updates.push('proof_files = ?');
      params.push(JSON.stringify(newFiles));
    }

    if (updates.length > 0) {
      params.push(id);
      await pool.query(`UPDATE finance_digital_expenses SET ${updates.join(', ')} WHERE id = ?`, params);
    }

    const [updatedRows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    await logHistory(req, 'Updated', expense.voucher_number, `Updated expense details`);
    res.json({ success: true, message: 'Digital expense updated successfully', data: mapExpenseRowToCamelCase(updatedRows[0]) });
  } catch (error) {
    if (req.files && req.files.length > 0) req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
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

    if (!['Approved', 'Declined', 'Pending', 'Response Submitted'].includes(status)) {
      return res.status(400).json({ success: false, message: 'Invalid status' });
    }

    if (status === 'Declined' && !reason) {
      return res.status(400).json({ success: false, message: 'Reason is required when declining' });
    }

    const [rows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    if (rows.length === 0) return res.status(404).json({ success: false, message: 'Expense not found' });
    const expense = rows[0];

    if (req.user?.orgId && expense.orgId !== null && expense.orgId !== req.user.orgId && expense.orgId !== '6a05b2c6aef99160d927b0bf' && expense.orgId !== '69df6eecb73c1ec7596c07c1') {
      return res.status(403).json({ success: false, message: 'Unauthorized access to expense' });
    }

    let managerReason = status === 'Declined' ? reason : null;
    let approvedAt = status === 'Approved' ? new Date() : null;

    await pool.query(
      `UPDATE finance_digital_expenses SET status = ?, manager_reason = ?, approved_at = ? WHERE id = ?`,
      [status, managerReason, approvedAt, id]
    );

    const [updatedRows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    await logHistory(req, status === 'Pending' ? 'Reverted' : status, expense.voucher_number, `Changed status to ${status}`);
    res.json({ success: true, message: `Expense ${status.toLowerCase()} successfully`, data: mapExpenseRowToCamelCase(updatedRows[0]) });
  } catch (error) {
    handleError(res, 500, 'Error updating digital expense status', error);
  }
});

// ============================================================================
// SUBMIT REBUTTAL (EMPLOYEE)
// ============================================================================
router.put('/:id/rebuttal', upload.array('rebuttalProofFiles', 5), async (req, res) => {
  try {
    const { id } = req.params;
    const { employeeResponse } = req.body;

    const [rows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    if (rows.length === 0) {
      if (req.files && req.files.length > 0) req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
      return res.status(404).json({ success: false, message: 'Expense not found' });
    }
    const expense = rows[0];

    if (expense.status !== 'Declined') {
      if (req.files && req.files.length > 0) req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
      return res.status(400).json({ success: false, message: 'Only declined expenses can be rebutted' });
    }

    let updates = ['status = ?', 'employee_response = ?', 'employee_response_at = NOW()'];
    let params = ['Response Submitted', employeeResponse || null];

    if (req.files && req.files.length > 0) {
      if (expense.rebuttal_proof_files) {
        const oldFiles = JSON.parse(expense.rebuttal_proof_files);
        oldFiles.forEach(pf => {
          const absPath = path.join(process.cwd(), pf.path || ('uploads/digital_expenses/' + pf.filename));
          if (fs.existsSync(absPath)) fs.unlinkSync(absPath);
        });
      }
      const newFiles = req.files.map(f => ({
        filename: f.filename,
        originalName: f.originalname,
        path: 'uploads/digital_expenses/' + f.filename,
        size: f.size,
        mimetype: f.mimetype
      }));
      updates.push('rebuttal_proof_files = ?');
      params.push(JSON.stringify(newFiles));
    }

    params.push(id);
    await pool.query(`UPDATE finance_digital_expenses SET ${updates.join(', ')} WHERE id = ?`, params);

    const [updatedRows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    await logHistory(req, 'Rebuttal Submitted', expense.voucher_number, `Employee submitted a response/explanation`);
    res.json({ success: true, message: 'Response submitted successfully', data: mapExpenseRowToCamelCase(updatedRows[0]) });
  } catch (error) {
    if (req.files && req.files.length > 0) req.files.forEach(f => { if (fs.existsSync(f.path)) fs.unlinkSync(f.path); });
    handleError(res, 500, 'Error submitting rebuttal', error);
  }
});

// ============================================================================
// DELETE DIGITAL EXPENSE
// ============================================================================
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const [rows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    if (rows.length === 0) return res.status(404).json({ success: false, message: 'Expense not found' });
    const expense = rows[0];

    if (req.user?.orgId && expense.orgId !== null && expense.orgId !== req.user.orgId && expense.orgId !== '6a05b2c6aef99160d927b0bf' && expense.orgId !== '69df6eecb73c1ec7596c07c1') {
      return res.status(403).json({ success: false, message: 'Unauthorized' });
    }

    if (expense.proof_files) {
      const oldFiles = JSON.parse(expense.proof_files);
      oldFiles.forEach(pf => {
        const absPath = path.join(process.cwd(), pf.path || ('uploads/digital_expenses/' + pf.filename));
        if (fs.existsSync(absPath)) fs.unlinkSync(absPath);
      });
    }

    await pool.query(`DELETE FROM finance_digital_expenses WHERE id = ?`, [id]);
    await logHistory(req, 'Deleted', expense.voucher_number, `Deleted expense voucher`);
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
    const orgId = req.user?.orgId || null;
    const addedBy = req.user?.email || 'System';

    let sqlCount = `SELECT COUNT(*) as c FROM finance_digital_expenses`;
    let countParams = [];
    if (branchId) {
      sqlCount += ` WHERE branchId = ?`;
      countParams.push(branchId);
    }
    const [countResult] = await pool.query(sqlCount, countParams);
    let currentCount = countResult[0].c;

    const insertPromises = [];
    let imported = 0;

    for (const exp of expenses) {
      if (!exp.date || !exp.amount || !exp.expenseCategory) continue;
      currentCount++;
      const voucherNumber = `DE${String(currentCount).padStart(4, '0')}`;

      const sqlInsert = `INSERT INTO finance_digital_expenses 
        (voucher_number, expense_date, amount, payment_method, amount_paid_to, amount_in_words, 
         on_account_of, expense_category, received_by, status, added_by, orgId, branchId) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

      const insertParams = [
        voucherNumber, exp.date, parseFloat(exp.amount), exp.paymentMethod || null, exp.amountPaidTo || null,
        exp.amountInWords || null, exp.onAccountOf || null, exp.expenseCategory, exp.receivedBy || null,
        'Pending', addedBy, orgId, branchId
      ];
      insertPromises.push(pool.query(sqlInsert, insertParams));
      imported++;
    }

    if (insertPromises.length > 0) {
      await Promise.all(insertPromises);
      await logHistory(req, 'Bulk Imported', null, `Bulk imported ${imported} expenses`);
    }

    res.json({ success: true, message: `${imported} expenses imported successfully` });
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
    let sql = `SELECT * FROM finance_digital_expense_history WHERE 1=1`;
    const params = [];

    if (req.user?.orgId) {
      sql += ` AND (orgId = ? OR orgId IS NULL OR orgId = '6a05b2c6aef99160d927b0bf' OR orgId = '69df6eecb73c1ec7596c07c1')`;
      params.push(req.user.orgId);
    }

    let branchFilterIds = [];
    if (req.query.branchIds && req.query.branchIds.trim() !== '' && req.query.branchIds.trim() !== 'ALL') {
      branchFilterIds = req.query.branchIds.split(',').map(s => s.trim()).filter(Boolean);
    } else if (req.branchFilter && typeof req.branchFilter.branchId === 'string') {
      branchFilterIds = [req.branchFilter.branchId];
    } else if (req.branchFilter && req.branchFilter.branchId && Array.isArray(req.branchFilter.branchId.$in)) {
      branchFilterIds = req.branchFilter.branchId.$in;
    }

    if (branchFilterIds.length > 0) {
      const placeholders = branchFilterIds.map(() => '?').join(',');
      sql += ` AND branchId IN (${placeholders})`;
      params.push(...branchFilterIds);
    }

    if (req.user && req.user.role !== 'admin' && req.user.role !== 'owner') {
      const email = req.user.email;
      sql += ` AND (performed_by = ? OR voucher_number IN (SELECT voucher_number FROM finance_digital_expenses WHERE added_by = ?))`;
      params.push(email, email);
    }

    sql += ` ORDER BY created_at DESC`;
    const [rows] = await pool.query(sql, params);

    const history = rows.map(r => ({
      _id: r.id,
      id: r.id,
      action: r.action,
      voucherNumber: r.voucher_number,
      details: r.details,
      performedBy: r.performed_by,
      userId: r.employee_id,
      orgId: r.orgId,
      branchId: r.branchId,
      createdAt: r.created_at,
      updatedAt: r.updated_at
    }));

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
    const [rows] = await pool.query(`SELECT * FROM finance_digital_expenses`);
    res.json({ success: true, count: rows.length, data: rows.map(mapExpenseRowToCamelCase) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/:id/pdf', async (req, res) => {
  try {
    const { id } = req.params;
    const [rows] = await pool.query(`SELECT * FROM finance_digital_expenses WHERE id = ?`, [id]);
    if (rows.length === 0) return res.status(404).json({ success: false, error: 'Expense not found' });

    const expenseRow = rows[0];
    const expense = mapExpenseRowToCamelCase(expenseRow);

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
        if (!effOrgId && expense.addedBy) {
          const user = await mongoose.connection.db.collection('billing_users').findOne({ email: expense.addedBy });
          if (user && user.organizations?.length > 0) {
            effOrgId = user.organizations[0].orgId;
            if (!effBranchId && user.organizations[0].allowedBranches?.length > 0) {
              effBranchId = user.organizations[0].allowedBranches[0];
            }
          }
        }

        if (effOrgId) {
          orgData = await getEffectiveOrgData(effOrgId, effBranchId, mongoose.connection.db);
        }
      }
    } catch (e) {
      console.error("DEBUG ERROR: ", e);
    }
    let displayName = orgData?._orgName?.toUpperCase() || orgData?.orgName?.toUpperCase() || 'ABRA FINANCE';
    if (orgData && orgData.orgName && orgData._orgName && orgData.orgName !== orgData._orgName) {
      displayName = `${orgData._orgName.toUpperCase()} - ${orgData.orgName.toUpperCase()}`;
    }

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

    const sigRelPath = orgData?.digitalSignaturePath || 'uploads/org-signatures/sig-69bd251dd852a7f1531cb66d-1776835239590.png';
    let actualSigH = 0;
    let actualSigW = 0;
    let hasSig = false;
    
    let sigBuf = null;
    let sigExt = '.png';
    if (orgData?.signatureBase64) {
      const match = orgData.signatureBase64.match(/^data:image\/(\w+);base64,(.*)$/);
      if (match) {
        sigExt = '.' + match[1].replace('jpeg', 'jpg');
        sigBuf = Buffer.from(match[2], 'base64');
      }
    } else if (sigRelPath) {
      const sigAbsPath = path.join(process.cwd(), sigRelPath.replace(/^\//, ''));
      try { if (fs.existsSync(sigAbsPath)) { sigBuf = fs.readFileSync(sigAbsPath); sigExt = path.extname(sigAbsPath).toLowerCase(); } } catch (_) {}
    }

    if (isApproved && sigBuf) {
      try {
          let imgW = 100, imgH = 100;
          try {
            if (sigExt === '.png' && sigBuf.length > 24) {
              imgW = sigBuf.readUInt32BE(16);
              imgH = sigBuf.readUInt32BE(20);
            } else if ((sigExt === '.jpg' || sigExt === '.jpeg') && sigBuf.length > 4) {
              let i = 2;
              while (i < sigBuf.length - 8) {
                if (sigBuf[i] === 0xFF && sigBuf[i + 1] >= 0xC0 && sigBuf[i + 1] <= 0xC3) {
                  imgH = sigBuf.readUInt16BE(i + 5);
                  imgW = sigBuf.readUInt16BE(i + 7);
                  break;
                }
                i += 2 + sigBuf.readUInt16BE(i + 2);
              }
            }
          } catch (_) { }
          const scale = Math.min(160 / imgW, 70 / imgH);
          actualSigW = Math.round(imgW * scale);
          actualSigH = Math.round(imgH * scale);
          hasSig = true;
          // Image added here
          doc.image(sigBuf, 40 + (160 - actualSigW) / 2, y, { width: actualSigW, height: actualSigH });
          y += actualSigH;
      } catch (e) { console.warn('Signature error:', e.message); }
    }

    doc.moveTo(40, y).lineTo(200, y).lineWidth(1).strokeColor('#000000').stroke();
    doc.fillColor('#000000').font('Helvetica-Bold').fontSize(10).text('Prepared By', 40, y + 5, { width: 160, align: 'center' });
    let preparerName = 'Accountant';
    if (expense.addedByName) {
      preparerName = expense.addedByName;
    } else if (expense.addedBy) {
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
          const absPath = path.join(process.cwd(), proof.path || ('uploads/digital_expenses/' + proof.filename));
          let imageSource = null;

          if (fs.existsSync(absPath)) {
            imageSource = absPath;
          } else {
            // Legacy Abra Flow X proxy fetching removed as requested.
          }

          if (imageSource) {
            doc.image(imageSource, imgX, imgY, { fit: [250, 250], align: 'center' });
            if (imgX === 40) {
              imgX = 305;
            } else {
              imgX = 40;
              imgY += 270;
            }
          }
        } catch (e) {
          console.log("PDF img error", e.message);
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
