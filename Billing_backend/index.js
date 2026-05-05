// index.js — Abra Finance Module Backend

const express  = require('express');
const http     = require('http');
const cors     = require('cors');
const mongoose = require('mongoose');
const path     = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const { connectFinanceDB }                        = require('./config/database');
const { verifyFinanceJWT, requireOwnerOrAdmin }   = require('./middleware/finance_jwt');

const app    = express();
const server = http.createServer(app);
const PORT   = process.env.PORT || 3002;

// ─── CORS ─────────────────────────────────────────────────────────────────────
const allowed = (process.env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim());
app.use(cors({
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);
    if (origin.includes('localhost') || origin.includes('127.0.0.1') || allowed.includes(origin))
      return cb(null, true);
    cb(new Error('Not allowed by CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-branch-ids', 'x-org-ids'],
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// ─── DB MIDDLEWARE ─────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  if (req.path === '/health') return next();
  if (mongoose.connection.readyState !== 1)
    return res.status(503).json({ success: false, message: 'Database not ready' });
  req.db = mongoose.connection.db;
  next();
});

// ─── HEALTH ───────────────────────────────────────────────────────────────────
app.get('/health', (_, res) => res.json({
  status: 'ok',
  service: 'abra-finance-module',
  timestamp: new Date().toISOString(),
  db: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
}));

// ─── PUBLIC ROUTES (no JWT) ───────────────────────────────────────────────────
app.use('/api/finance/auth',  require('./routes/finance_auth'));

// ─── PDF TOKEN PROMOTION ──────────────────────────────────────────────────────
// For PDF preview routes, the frontend fetches with ?token= in the URL.
// Promote it to Authorization header so verifyFinanceJWT can validate it.
app.use((req, res, next) => {
  if (req.query.token && !req.headers.authorization) {
    req.headers.authorization = `Bearer ${req.query.token}`;
  }
  next();
});

// ─── PROTECTED ROUTES (JWT required) ─────────────────────────────────────────

// Branches
app.use('/api/finance/branches',      verifyFinanceJWT, require('./routes/branches'));

// ERP / User management
app.use('/api/finance/users',         verifyFinanceJWT, require('./routes/erp_users_management'));

// Dashboard & Home
app.use('/api/finance/dashboard',     verifyFinanceJWT, require('./routes/billing_dashboard'));
app.use('/api/finance/home',          verifyFinanceJWT, require('./routes/home_billing'));

// Sales
app.use('/api/finance/invoices', verifyFinanceJWT, require('./routes/invoices'));

// ── Reminder Settings routes ──────────────────────────────────────────────────
const { settingsRouter, initReminderScheduler } = require('./jobs/reminderScheduler');
app.use('/api/finance/reminder-settings', verifyFinanceJWT, settingsRouter);
app.use('/api/finance/recurring-invoices', verifyFinanceJWT, require('./routes/recurring-invoice'));
app.use('/api/finance/quotes',        verifyFinanceJWT, require('./routes/quotes'));
app.use('/api/finance/sales-orders',  verifyFinanceJWT, require('./routes/sales-order'));
app.use('/api/finance/customers',     verifyFinanceJWT, require('./routes/billing-customers'));
app.use('/api/finance/credit-notes',  verifyFinanceJWT, require('./routes/credit-notes'));
app.use('/api/finance/delivery-challans', verifyFinanceJWT, require('./routes/delivery_challans'));
app.use('/api/finance/eway-bills',        verifyFinanceJWT, require('./routes/eway_bill_routes'));
app.use('/api/finance/payments-received', verifyFinanceJWT, require('./routes/payments_received'));

// Purchases
app.use('/api/finance/bills',         verifyFinanceJWT, require('./routes/bill'));
app.use('/api/finance/recurring-bills', verifyFinanceJWT, require('./routes/recurring_bill'));
app.use('/api/finance/expenses',      verifyFinanceJWT, require('./routes/expenses'));
app.use('/api/finance/recurring-expenses', verifyFinanceJWT, require('./routes/recurring_expenses'));
app.use('/api/finance/purchase-orders', verifyFinanceJWT, require('./routes/purchase_order'));
app.use('/api/finance/vendors',       verifyFinanceJWT, require('./routes/billing_vendors'));
app.use('/api/billing-vendors',       verifyFinanceJWT, require('./routes/billing_vendors')); // legacy alias
app.use('/api/finance/vendor-credits', verifyFinanceJWT, require('./routes/vendor_credit'));
app.use('/api/finance/payments-made', verifyFinanceJWT, require('./routes/payment_made'));

// Accountant
app.use('/api/finance/chart-of-accounts',    verifyFinanceJWT, require('./routes/chart_of_accounts'));
app.use('/api/finance/manual-journals',      verifyFinanceJWT, require('./routes/manual_journal'));
app.use('/api/finance/currency-adjustments', verifyFinanceJWT, require('./routes/currency_adjustments'));
app.use('/api/finance/budgets',           verifyFinanceJWT, require('./routes/budgets'));
app.use('/api/finance/fixed-assets',      verifyFinanceJWT, require('./routes/fixed_assets'));
// ✅ FIX: Added verifyFinanceJWT — was publicly accessible before
app.use('/api/finance/reconciliation', verifyFinanceJWT, require('./routes/reconciliation_routes'));
// app.use('/api/finance/reconciliation-v1', verifyFinanceJWT, require('./routes/reconciliation_billing'));

// Items & Banking
app.use('/api/finance/items',         verifyFinanceJWT, require('./routes/new_item_billing'));
app.use('/api/finance/banking/transactions', verifyFinanceJWT, require('./routes/bank_transactions'));
app.use('/api/finance/banking',       verifyFinanceJWT, require('./routes/add_bank'));
app.use('/api/finance/accounts', verifyFinanceJWT, require('./routes/add_bank'));
app.use('/api/finance/transaction-rules', verifyFinanceJWT, require('./routes/transaction_rules'));


// Rate Cards
app.use('/api/finance/rate-cards',    verifyFinanceJWT, require('./routes/rate_cards'));
app.use('/api/finance/rate-card-billing', verifyFinanceJWT, require('./routes/rate_card_billing'));
app.use('/api/finance/rate-card-docs', verifyFinanceJWT, require('./routes/rate_card_document_upload'));
app.use('/api/finance/create-rate-card', verifyFinanceJWT, require('./routes/create_rate_card'));

// Time Tracking
app.use('/api/finance/projects',      verifyFinanceJWT, require('./routes/projects'));
app.use('/api/finance/timesheets',    verifyFinanceJWT, require('./routes/timesheets'));
app.use('/api/finance/timers', verifyFinanceJWT, require('./routes/timers'));
// Reports
app.use('/api/finance/reports',       verifyFinanceJWT, require('./routes/reports'));

// Billing router (contracts etc.)
app.use('/api/finance/billing',       verifyFinanceJWT, require('./routes/billing_router'));

// TMS — Ticket Management System (org-scoped)
app.use('/api/finance/tickets',       verifyFinanceJWT, require('./routes/tms'));

// Payment Gateway (Razorpay — run: npm install razorpay when going live)
// Webhook must be PUBLIC — Razorpay cannot send JWT
app.use(
  '/api/finance/payment-gateway/webhook',
  express.raw({ type: 'application/json' }),
  require('./routes/payment_gateway_routes')
);
// All other gateway routes — JWT protected
app.use('/api/finance/payment-gateway', verifyFinanceJWT, require('./routes/payment_gateway_routes'));

// Vendors (admin only)
app.use('/api/finance/vendor-management', verifyFinanceJWT, requireOwnerOrAdmin, require('./routes/vendors.routes'));



// TEMPORARY: Seed system accounts
app.post('/api/seed-accounts', async (req, res) => {
  try {
    const coa = require('./routes/chart_of_accounts');
    await coa.seedSystemAccounts();
    res.json({ success: true, message: 'System accounts seeded!' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ONE-TIME: Sync existing bank accounts to COA
app.get('/api/sync-bank-to-coa', async (req, res) => {
  try {
    const { ChartOfAccount } = require('./routes/chart_of_accounts');
    const PaymentAccount = mongoose.models.PaymentAccount || 
      require('./routes/add_bank').PaymentAccount;
    
    const accounts = await mongoose.connection.db
      .collection('paymentaccounts').find({}).toArray();
    
    const coaTypeMap = {
      'BANK_ACCOUNT': 'Other Current Asset',
      'BANK':         'Other Current Asset',
      'FUEL_CARD':    'Other Current Asset',
      'UPI':          'Other Current Asset',
      'FASTAG':       'Other Current Asset',
      'OTHER':        'Other Current Asset',
    };
    
    let created = 0;
    let skipped = 0;
    
    for (const acc of accounts) {
      const existing = await ChartOfAccount.findOne({ 
        accountName: acc.accountName 
      });
      
      if (!existing) {
        const coaType = coaTypeMap[acc.accountType] || 'Other Current Asset';
        await ChartOfAccount.create({
          accountName:     acc.accountName,
          accountType:     coaType,
          accountSubType:  acc.accountType,
          description:     `Auto-created for ${acc.accountType} - ${acc.accountName}`,
          currency:        'INR',
          isActive:        true,
          isSystemAccount: false,
          closingBalance:  acc.currentBalance || acc.openingBalance || 0,
          balanceType:     'Dr',
          createdBy:       'system',
        });
        created++;
        console.log(`✅ COA created for: ${acc.accountName}`);
      } else {
        skipped++;
        console.log(`ℹ️ Already exists: ${acc.accountName}`);
      }
    }
    
    res.json({ 
      success: true, 
      message: `Sync complete: ${created} created, ${skipped} skipped`,
      created,
      skipped
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ✅ FIX: Backfill routes locked — owner/admin only, emergency use
app.use('/api/backfill-invoice-coa', verifyFinanceJWT, requireOwnerOrAdmin);
app.use('/api/backfill-bank-coa',    verifyFinanceJWT, requireOwnerOrAdmin);
app.use('/api/backfill-payment-coa', verifyFinanceJWT, requireOwnerOrAdmin);

// ─── 404 ──────────────────────────────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ success: false, message: `Cannot ${req.method} ${req.path}` }));

// ─── ERROR ────────────────────────────────────────────────────────────────────
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
  console.error('❌ Unhandled error:', err.message);
  res.status(500).json({ success: false, message: err.message });
});

// ─── START ────────────────────────────────────────────────────────────────────
async function start() {
  await connectFinanceDB();
  initReminderScheduler();
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n✅ Abra Finance Backend running on port ${PORT}`);
    console.log(`   Health:      http://localhost:${PORT}/health`);
    console.log(`   Auth:        http://localhost:${PORT}/api/finance/auth`);
    console.log(`   Dashboard:   http://localhost:${PORT}/api/finance/dashboard`);
    console.log(`   Invoices:    http://localhost:${PORT}/api/finance/invoices`);
    console.log(`   Expenses:    http://localhost:${PORT}/api/finance/expenses\n`);
  });
}

start().catch(err => { console.error('❌ Fatal:', err.message); process.exit(1); });

process.on('SIGINT', async () => {
  await mongoose.connection.close();
  server.close(() => process.exit(0));
});
