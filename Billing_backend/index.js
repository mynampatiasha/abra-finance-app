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
  allowedHeaders: ['Content-Type', 'Authorization'],
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

// ERP / User management
app.use('/api/finance/users',         verifyFinanceJWT, require('./routes/erp_users_management'));

// Dashboard & Home
app.use('/api/finance/dashboard',     verifyFinanceJWT, require('./routes/billing_dashboard'));
app.use('/api/finance/home',          verifyFinanceJWT, require('./routes/home_billing'));

// Sales
app.use('/api/finance/invoices', verifyFinanceJWT, require('./routes/invoices'));
app.use('/api/finance/recurring-invoices', verifyFinanceJWT, require('./routes/recurring-invoice'));
app.use('/api/finance/quotes',        verifyFinanceJWT, require('./routes/quotes'));
app.use('/api/finance/sales-orders',  verifyFinanceJWT, require('./routes/sales-order'));
app.use('/api/finance/customers',     verifyFinanceJWT, require('./routes/billing-customers'));
app.use('/api/finance/credit-notes',  verifyFinanceJWT, require('./routes/credit-notes'));
app.use('/api/finance/delivery-challans', verifyFinanceJWT, require('./routes/delivery_challans'));
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
app.use('/api/finance/reconciliation',    verifyFinanceJWT, require('./routes/reconciliation_billing'));

// Items & Banking
app.use('/api/finance/items',         verifyFinanceJWT, require('./routes/new_item_billing'));
app.use('/api/finance/banking',       verifyFinanceJWT, require('./routes/add_bank'));
app.use('/api/finance/accounts', verifyFinanceJWT, require('./routes/add_bank')); 

// Rate Cards
app.use('/api/finance/rate-cards',    verifyFinanceJWT, require('./routes/rate_cards'));
app.use('/api/finance/rate-card-billing', verifyFinanceJWT, require('./routes/rate_card_billing'));
app.use('/api/finance/rate-card-docs', verifyFinanceJWT, require('./routes/rate_card_document_upload'));
app.use('/api/finance/create-rate-card', verifyFinanceJWT, require('./routes/create_rate_card'));

// Time Tracking
app.use('/api/finance/projects',      verifyFinanceJWT, require('./routes/projects'));
app.use('/api/finance/timesheets',    verifyFinanceJWT, require('./routes/timesheets'));

// Reports
app.use('/api/finance/reports',       verifyFinanceJWT, require('./routes/reports'));

// Billing router (contracts etc.)
app.use('/api/finance/billing',       verifyFinanceJWT, require('./routes/billing_router'));

// TMS — Ticket Management System (org-scoped)
app.use('/api/finance/tickets',       verifyFinanceJWT, require('./routes/tms'));

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

// ONE-TIME: Backfill COA entries for existing invoices
app.get('/api/backfill-invoice-coa', async (req, res) => {
  try {
    const { ChartOfAccount, AccountTransaction, postTransactionToCOA } = require('./routes/chart_of_accounts');

    // Get all system account IDs
    const [arAcc, salesAcc, taxAcc] = await Promise.all([
      ChartOfAccount.findOne({ accountName: 'Accounts Receivable', isSystemAccount: true }).lean(),
      ChartOfAccount.findOne({ accountName: 'Sales', isSystemAccount: true }).lean(),
      ChartOfAccount.findOne({ accountName: 'Tax Payable', isSystemAccount: true }).lean(),
    ]);

    if (!arAcc || !salesAcc || !taxAcc) {
      return res.status(400).json({ 
        success: false, 
        message: 'System accounts not found. Run /api/seed-accounts first.' 
      });
    }

    // Get all invoices from MongoDB
    const invoices = await mongoose.connection.db
      .collection('invoices')
      .find({})
      .toArray();

    console.log(`📋 Found ${invoices.length} invoices to backfill`);

    let created = 0;
    let skipped = 0;
    const errors = [];

    for (const invoice of invoices) {
      try {
        // Check if COA entry already exists for this invoice
        const existing = await AccountTransaction.findOne({
          referenceType: 'Invoice',
          referenceId: invoice._id,
          accountId: arAcc._id,
        });

        if (existing) {
          console.log(`ℹ️ Skipping ${invoice.invoiceNumber} — already posted`);
          skipped++;
          continue;
        }

        // Parse invoice date safely
        let txnDate = new Date(invoice.invoiceDate);
        if (isNaN(txnDate)) txnDate = new Date();

        const totalAmount = parseFloat(invoice.totalAmount) || 0;
        const subTotal   = parseFloat(invoice.subTotal)    || 0;
        const cgst       = parseFloat(invoice.cgst)        || 0;
        const sgst       = parseFloat(invoice.sgst)        || 0;
        const gst        = cgst + sgst;

        // Post AR debit
        await postTransactionToCOA({
          accountId:       arAcc._id,
          date:            txnDate,
          description:     `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
          referenceType:   'Invoice',
          referenceId:     invoice._id,
          referenceNumber: invoice.invoiceNumber,
          debit:           totalAmount,
          credit:          0,
        });

        // Post Sales credit
        await postTransactionToCOA({
          accountId:       salesAcc._id,
          date:            txnDate,
          description:     `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
          referenceType:   'Invoice',
          referenceId:     invoice._id,
          referenceNumber: invoice.invoiceNumber,
          debit:           0,
          credit:          subTotal,
        });

        // Post Tax Payable credit (only if GST > 0)
        if (gst > 0) {
          await postTransactionToCOA({
            accountId:       taxAcc._id,
            date:            txnDate,
            description:     `GST on Invoice ${invoice.invoiceNumber}`,
            referenceType:   'Invoice',
            referenceId:     invoice._id,
            referenceNumber: invoice.invoiceNumber,
            debit:           0,
            credit:          gst,
          });
        }

        console.log(`✅ Backfilled: ${invoice.invoiceNumber} — AR ₹${totalAmount}, Sales ₹${subTotal}, GST ₹${gst}`);
        created++;

      } catch (err) {
        console.error(`❌ Failed: ${invoice.invoiceNumber} —`, err.message);
        errors.push(`${invoice.invoiceNumber}: ${err.message}`);
      }
    }

    res.json({
      success: true,
      message: `Backfill complete: ${created} posted, ${skipped} skipped`,
      created,
      skipped,
      errors,
    });

  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});


app.get('/api/backfill-bank-coa', async (req, res) => {
  try {
    const { ChartOfAccount, postTransactionToCOA } = require('./routes/chart_of_accounts');
    
    const accounts = await mongoose.connection.db
      .collection('paymentaccounts').find({}).toArray();
    
    let created = 0;
    for (const acc of accounts) {
      const coaAcc = await ChartOfAccount.findOne({ accountName: acc.accountName });
      if (!coaAcc) continue;
      
      const balance = parseFloat(acc.currentBalance || acc.openingBalance || 0);
      if (balance <= 0) continue;

      await postTransactionToCOA({
        accountId:       coaAcc._id,
        date:            new Date(acc.createdAt || Date.now()),
        description:     `Opening balance - ${acc.accountName}`,
        referenceType:   'Opening Balance',
        referenceId:     acc._id,
        referenceNumber: 'OPENING',
        debit:           balance,
        credit:          0,
      });
      
      console.log(`✅ Opening balance posted: ${acc.accountName} ₹${balance}`);
      created++;
    }
    
    res.json({ success: true, message: `Done: ${created} opening balances posted` });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

app.get('/api/backfill-payment-coa', async (req, res) => {
  try {
    const { ChartOfAccount, AccountTransaction, postTransactionToCOA } = require('./routes/chart_of_accounts');

    const payments = await mongoose.connection.db
      .collection('payments_received').find({}).toArray();

    let created = 0;
    let skipped = 0;

    for (const payment of payments) {
      // Check if already posted correctly (not to Undeposited Funds)
      const existing = await AccountTransaction.findOne({
        referenceType: 'Payment',
        referenceId:   payment._id,
      });

      // Delete wrong Undeposited Funds entries if they exist
      if (existing) {
        await AccountTransaction.deleteMany({
          referenceType: 'Payment',
          referenceId:   payment._id,
        });
        console.log(`🗑️ Deleted wrong COA entries for payment ${payment.paymentNumber}`);
      }

      // Resolve correct deposit account name
      let depositName = 'Undeposited Funds';
      if (payment.depositTo) {
        const { ObjectId } = require('mongodb');
        if (ObjectId.isValid(payment.depositTo)) {
          const bankAcc = await mongoose.connection.db
            .collection('paymentaccounts')
            .findOne({ _id: new ObjectId(payment.depositTo) });
          if (bankAcc) depositName = bankAcc.accountName;
        } else {
          depositName = payment.depositTo;
        }
      }

      // Find COA accounts
      const [depositAcc, arAcc] = await Promise.all([
        ChartOfAccount.findOne({ accountName: depositName }),
        ChartOfAccount.findOne({ accountName: 'Accounts Receivable', isSystemAccount: true }),
      ]);

      let txnDate = new Date(payment.paymentDate);
      if (isNaN(txnDate)) txnDate = new Date();

      const amount = parseFloat(payment.amountReceived) || 0;

      if (depositAcc) await postTransactionToCOA({
        accountId:       depositAcc._id,
        date:            txnDate,
        description:     `Payment received - ${payment.paymentNumber} - ${payment.customerName}`,
        referenceType:   'Payment',
        referenceId:     payment._id,
        referenceNumber: payment.paymentNumber,
        debit:           amount,
        credit:          0,
      });

      if (arAcc) await postTransactionToCOA({
        accountId:       arAcc._id,
        date:            txnDate,
        description:     `Payment received - ${payment.paymentNumber} - ${payment.customerName}`,
        referenceType:   'Payment',
        referenceId:     payment._id,
        referenceNumber: payment.paymentNumber,
        debit:           0,
        credit:          amount,
      });

      console.log(`✅ Payment ${payment.paymentNumber} → ${depositName} ₹${amount}`);
      created++;
    }

    res.json({ 
      success: true, 
      message: `Done: ${created} payments reposted`,
      created 
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

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
