// ============================================================================
// DASHBOARD API - ZOHO BOOKS MONTHLY BREAKDOWN (COMPLETE VERSION)
// ============================================================================
// File: backend/routes/home_billing.js
// Features: 
// 1. Monthly breakdown for Income/Expense (12 months of data)
// 2. Monthly breakdown for Cash Flow (12 months of data) - WITH CUMULATIVE BALANCE
// 3. Accrual/Cash basis support
// 4. Fiscal year aware (Apr-Mar for India)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Format currency to Indian Rupee
function formatCurrency(amount) {
  return `₹${amount.toFixed(2)}`;
}

// Get fiscal year dates (April 1 to March 31 - Indian FY)
function getFiscalYearDates() {
  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth(); // 0-11
  
  let fiscalYearStart, fiscalYearEnd;
  
  if (currentMonth >= 3) {
    // April-December: FY is current year to next year
    fiscalYearStart = new Date(currentYear, 3, 1); // April 1
    fiscalYearEnd = new Date(currentYear + 1, 2, 31); // March 31 next year
  } else {
    // January-March: FY is last year to current year
    fiscalYearStart = new Date(currentYear - 1, 3, 1); // April 1 last year
    fiscalYearEnd = new Date(currentYear, 2, 31); // March 31 this year
  }
  
  return { start: fiscalYearStart, end: fiscalYearEnd };
}

// Get date range based on period
function getDateRange(period) {
  const now = new Date();
  let startDate, endDate;
  
  switch (period) {
    case 'this_month':
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
      endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0);
      break;
      
    case 'last_month':
      startDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      endDate = new Date(now.getFullYear(), now.getMonth(), 0);
      break;
      
    case 'this_quarter':
      const currentQuarter = Math.floor(now.getMonth() / 3);
      startDate = new Date(now.getFullYear(), currentQuarter * 3, 1);
      endDate = new Date(now.getFullYear(), (currentQuarter + 1) * 3, 0);
      break;
      
    case 'fiscal_year':
    default:
      const fiscalYear = getFiscalYearDates();
      startDate = fiscalYear.start;
      endDate = fiscalYear.end;
      break;
  }
  
  return { startDate, endDate };
}

// Get month name in short format (e.g., "Apr 2025")
function getMonthName(date) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${months[date.getMonth()]} ${date.getFullYear()}`;
}

// Generate 12 months array for fiscal year
function generateFiscalYearMonths() {
  const fiscalYear = getFiscalYearDates();
  const months = [];
  
  let current = new Date(fiscalYear.start);
  
  for (let i = 0; i < 12; i++) {
    const monthStart = new Date(current.getFullYear(), current.getMonth(), 1);
    const monthEnd = new Date(current.getFullYear(), current.getMonth() + 1, 0);
    
    months.push({
      name: getMonthName(current),
      startDate: monthStart,
      endDate: monthEnd,
      monthIndex: current.getMonth(),
      year: current.getFullYear()
    });
    
    current = new Date(current.getFullYear(), current.getMonth() + 1, 1);
  }
  
  return months;
}

// ✅ HELPER: Convert payment date to Date object (handles both strings and Date objects)
function parsePaymentDate(paymentDate) {
  if (!paymentDate) return null;
  
  // If already a Date object
  if (paymentDate instanceof Date) {
    return paymentDate;
  }
  
  // If it's a string, parse it
  if (typeof paymentDate === 'string') {
    return new Date(paymentDate);
  }
  
  return null;
}

// ============================================================================
// CALCULATE TOTAL RECEIVABLES
// ============================================================================

async function calculateReceivables() {
  try {
    console.log('📊 Calculating Total Receivables...');
    
    const db = mongoose.connection.db;
    
    const unpaidInvoices = await db.collection('invoices').find({
      status: { $in: ['SENT', 'UNPAID', 'PARTIALLY_PAID', 'OVERDUE'] }
    }).toArray();
    
    let totalReceivables = 0;
    let currentAmount = 0;
    let overdueAmount = 0;
    
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    unpaidInvoices.forEach(invoice => {
      const amountDue = invoice.amountDue || 0;
      totalReceivables += amountDue;
      
      const dueDate = new Date(invoice.dueDate);
      dueDate.setHours(0, 0, 0, 0);
      
      if (dueDate >= today) {
        currentAmount += amountDue;
      } else {
        overdueAmount += amountDue;
      }
    });
    
    console.log(`   Total: ${formatCurrency(totalReceivables)}`);
    console.log(`   Current: ${formatCurrency(currentAmount)}`);
    console.log(`   Overdue: ${formatCurrency(overdueAmount)}`);
    
    return {
      total: totalReceivables,
      current: currentAmount,
      overdue: overdueAmount,
      totalFormatted: formatCurrency(totalReceivables),
      currentFormatted: formatCurrency(currentAmount),
      overdueFormatted: formatCurrency(overdueAmount),
      invoiceCount: unpaidInvoices.length
    };
  } catch (error) {
    console.error('❌ Error calculating receivables:', error);
    throw error;
  }
}

// ============================================================================
// CALCULATE TOTAL PAYABLES
// ============================================================================

async function calculatePayables() {
  try {
    console.log('📊 Calculating Total Payables...');
    
    return {
      total: 0,
      current: 0,
      overdue: 0,
      totalFormatted: formatCurrency(0),
      currentFormatted: formatCurrency(0),
      overdueFormatted: formatCurrency(0),
      billCount: 0
    };
  } catch (error) {
    console.error('❌ Error calculating payables:', error);
    throw error;
  }
}

// ============================================================================
// CALCULATE CASH FLOW WITH MONTHLY BREAKDOWN - ✅ WITH CUMULATIVE BALANCE
// ============================================================================

async function calculateCashFlow(period = 'fiscal_year') {
  try {
    console.log(`\n📊 Calculating Cash Flow with Monthly Breakdown for: ${period}...`);
    console.log('='.repeat(80));
    
    const { startDate, endDate } = getDateRange(period);
    const db = mongoose.connection.db;
    
    console.log(`   Period: ${startDate.toISOString().split('T')[0]} to ${endDate.toISOString().split('T')[0]}`);
    
    // Generate fiscal year months
    const fiscalMonths = generateFiscalYearMonths();
    
    // ✅ Initialize monthly data WITH balance field
    const monthlyData = fiscalMonths.map(month => ({
      month: month.name,
      incoming: 0,
      outgoing: 0,
      net: 0,
      balance: 0  // ✅ CUMULATIVE BALANCE
    }));
    
    // ✅ STEP 1: Calculate OPENING BALANCE (payments received BEFORE fiscal year start)
    const allPayments = await db.collection('payments_received').find({
      status: { $ne: 'void' }
    }).toArray();
    
    console.log(`   📦 Total payments in database: ${allPayments.length}`);
    
    let openingBalance = 0;
    let totalIncoming = 0;
    let totalOutgoing = 0; // TODO: Add bills/expenses
    let paymentsInPeriod = 0;
    let paymentsBeforePeriod = 0;
    
    // ✅ STEP 2: Categorize payments into BEFORE period and DURING period
    allPayments.forEach((payment, index) => {
      const paymentDate = parsePaymentDate(payment.paymentDate);
      
      if (!paymentDate) {
        console.log(`   ⚠️  Payment ${index + 1}: Invalid date format:`, payment.paymentDate);
        return;
      }
      
      const amount = payment.amountReceived || 0;
      
      // ✅ Payments BEFORE fiscal year = Opening Balance
      if (paymentDate < startDate) {
        openingBalance += amount;
        paymentsBeforePeriod++;
      }
      // ✅ Payments DURING fiscal year = Incoming for this period
      else if (paymentDate >= startDate && paymentDate <= endDate) {
        totalIncoming += amount;
        paymentsInPeriod++;
        
        // Find which month this payment belongs to
        const monthIndex = fiscalMonths.findIndex(month => {
          return paymentDate >= month.startDate && paymentDate <= month.endDate;
        });
        
        if (monthIndex !== -1) {
          monthlyData[monthIndex].incoming += amount;
          monthlyData[monthIndex].net = monthlyData[monthIndex].incoming - monthlyData[monthIndex].outgoing;
        }
        
        // Log first 5 payments for debugging
        if (paymentsInPeriod <= 5) {
          console.log(`   ✅ Payment ${paymentsInPeriod}: ${payment.paymentNumber || 'N/A'} - ${formatCurrency(amount)} on ${paymentDate.toISOString().split('T')[0]}`);
        }
      }
    });
    
    // ✅ STEP 3: Calculate CUMULATIVE BALANCE starting from opening balance
    let runningBalance = openingBalance; // ✅ Start with cash before fiscal year
    for (let i = 0; i < monthlyData.length; i++) {
      runningBalance += monthlyData[i].incoming - monthlyData[i].outgoing;
      monthlyData[i].balance = runningBalance;
    }
    
    const closingBalance = runningBalance; // Final balance at end of fiscal year
    
    console.log('─'.repeat(80));
    console.log(`   📊 RESULTS:`);
    console.log(`      Payments before period: ${paymentsBeforePeriod} (Opening Balance: ${formatCurrency(openingBalance)})`);
    console.log(`      Payments in period: ${paymentsInPeriod}/${allPayments.length}`);
    console.log(`      Total Incoming: ${formatCurrency(totalIncoming)}`);
    console.log(`      Total Outgoing: ${formatCurrency(totalOutgoing)}`);
    console.log(`      Opening Balance: ${formatCurrency(openingBalance)}`);
    console.log(`      Closing Balance: ${formatCurrency(closingBalance)}`);
    
    // ✅ Log monthly breakdown WITH cumulative balance
    console.log(`   📅 MONTHLY BREAKDOWN (WITH CUMULATIVE BALANCE):`);
    let hasData = false;
    monthlyData.forEach((month, i) => {
      if (month.incoming > 0 || month.outgoing > 0 || month.balance !== 0) {
        console.log(`      ${i + 1}. ${month.month}: Incoming ${formatCurrency(month.incoming)}, Outgoing ${formatCurrency(month.outgoing)}, Balance ${formatCurrency(month.balance)}`);
        hasData = true;
      }
    });
    
    if (!hasData) {
      console.log(`      (No payments found in any month)`);
    }
    
    console.log('='.repeat(80) + '\n');
    
    return {
      incoming: totalIncoming,
      outgoing: totalOutgoing,
      openingBalance: openingBalance,  // ✅ Now includes opening balance
      closingBalance: closingBalance,  // ✅ Correct closing balance
      incomingFormatted: formatCurrency(totalIncoming),
      outgoingFormatted: formatCurrency(totalOutgoing),
      openingBalanceFormatted: formatCurrency(openingBalance),
      closingBalanceFormatted: formatCurrency(closingBalance),
      startDate: startDate,
      endDate: endDate,
      period: period,
      monthlyData: monthlyData  // ✅ Now includes 'balance' field for each month
    };
  } catch (error) {
    console.error('❌ Error calculating cash flow:', error);
    throw error;
  }
}

// ============================================================================
// CALCULATE INCOME AND EXPENSE WITH MONTHLY BREAKDOWN - ✅ FIXED FOR ANY DATE FORMAT
// ============================================================================

async function calculateIncomeAndExpense(period = 'fiscal_year', basis = 'accrual') {
  try {
    console.log(`\n📊 Calculating Income and Expense (${basis}) with Monthly Breakdown for: ${period}...`);
    
    const { startDate, endDate } = getDateRange(period);
    const db = mongoose.connection.db;
    
    // Generate fiscal year months
    const fiscalMonths = generateFiscalYearMonths();
    
    // Initialize monthly data
    const monthlyData = fiscalMonths.map(month => ({
      month: month.name,
      income: 0,
      expense: 0,
      net: 0
    }));
    
    if (basis === 'accrual') {
      // ✅ ACCRUAL BASIS: Based on invoice date
      console.log('   Using Accrual Basis (based on invoice date)...');
      
      const allInvoices = await db.collection('invoices').find({}).toArray();
      
      console.log(`   Found ${allInvoices.length} total invoices in database`);
      
      // Group invoices by month
      allInvoices.forEach(invoice => {
        const invoiceDate = parsePaymentDate(invoice.invoiceDate);
        
        if (!invoiceDate) return;
        
        const monthIndex = fiscalMonths.findIndex(month => {
          return invoiceDate >= month.startDate && invoiceDate <= month.endDate;
        });
        
        if (monthIndex !== -1) {
          monthlyData[monthIndex].income += invoice.totalAmount || 0;
          monthlyData[monthIndex].net = monthlyData[monthIndex].income - monthlyData[monthIndex].expense;
        }
      });
      
    } else {
      // ✅ CASH BASIS: Based on actual payment date
      console.log('   Using Cash Basis (based on payment date)...');
      
      const allPayments = await db.collection('payments_received').find({
        status: { $ne: 'void' }
      }).toArray();
      
      console.log(`   Found ${allPayments.length} total payments in database`);
      
      // Group payments by month
      allPayments.forEach(payment => {
        const paymentDate = parsePaymentDate(payment.paymentDate);
        
        if (!paymentDate) return;
        
        const monthIndex = fiscalMonths.findIndex(month => {
          return paymentDate >= month.startDate && paymentDate <= month.endDate;
        });
        
        if (monthIndex !== -1) {
          monthlyData[monthIndex].income += payment.amountReceived || 0;
          monthlyData[monthIndex].net = monthlyData[monthIndex].income - monthlyData[monthIndex].expense;
        }
      });
    }
    
    // Calculate totals
    const totalIncome = monthlyData.reduce((sum, month) => sum + month.income, 0);
    const totalExpense = monthlyData.reduce((sum, month) => sum + month.expense, 0);
    
    console.log(`   ✅ Total Income: ${formatCurrency(totalIncome)}`);
    console.log(`   ✅ Total Expense: ${formatCurrency(totalExpense)}`);
    console.log(`   ✅ Monthly data calculated for ${monthlyData.length} months`);
    
    // Log each month's data
    let hasData = false;
    monthlyData.forEach((month, i) => {
      if (month.income > 0 || month.expense > 0) {
        console.log(`      ${i + 1}. ${month.month}: Income ${formatCurrency(month.income)}, Expense ${formatCurrency(month.expense)}`);
        hasData = true;
      }
    });
    
    if (!hasData) {
      console.log(`      (No income/expense found in any month)`);
    }
    
    return {
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      totalIncomeFormatted: formatCurrency(totalIncome),
      totalExpenseFormatted: formatCurrency(totalExpense),
      netProfit: totalIncome - totalExpense,
      netProfitFormatted: formatCurrency(totalIncome - totalExpense),
      startDate: startDate,
      endDate: endDate,
      period: period,
      basis: basis,
      monthlyData: monthlyData
    };
  } catch (error) {
    console.error('❌ Error calculating income and expense:', error);
    throw error;
  }
}

// ============================================================================
// CALCULATE PROJECTS SUMMARY
// ============================================================================

async function calculateProjectsSummary() {
  try {
    console.log('📊 Calculating Projects Summary...');
    
    return {
      projects: [],
      totalProjects: 0
    };
  } catch (error) {
    console.error('❌ Error calculating projects:', error);
    throw error;
  }
}

// ============================================================================
// CALCULATE BANK ACCOUNTS SUMMARY
// ============================================================================

async function calculateBankAccountsSummary() {
  try {
    console.log('📊 Calculating Bank Accounts Summary...');
    
    return {
      accounts: [],
      totalAccounts: 0,
      totalBalance: 0
    };
  } catch (error) {
    console.error('❌ Error calculating bank accounts:', error);
    throw error;
  }
}

// ============================================================================
// CALCULATE ACCOUNT WATCHLIST
// ============================================================================

async function calculateAccountWatchlist(basis = 'accrual') {
  try {
    console.log(`📊 Calculating Account Watchlist (${basis})...`);
    
    return {
      accounts: [],
      totalAccounts: 0,
      basis: basis
    };
  } catch (error) {
    console.error('❌ Error calculating watchlist:', error);
    throw error;
  }
}

// ============================================================================
// API ROUTES
// ============================================================================

/**
 * GET /api/dashboard/summary
 * Get complete dashboard summary with monthly breakdowns
 */
router.get('/summary', async (req, res) => {
  try {
    console.log('\n' + '📊'.repeat(50));
    console.log('DASHBOARD SUMMARY REQUEST (WITH MONTHLY BREAKDOWNS)');
    console.log('📊'.repeat(50));
    
    const { basis = 'accrual' } = req.query;
    
    // Calculate all dashboard components in parallel
    const [receivables, payables, cashFlow, incomeExpense, projects, bankAccounts, watchlist] = 
      await Promise.all([
        calculateReceivables(),
        calculatePayables(),
        calculateCashFlow('fiscal_year'),
        calculateIncomeAndExpense('fiscal_year', basis),
        calculateProjectsSummary(),
        calculateBankAccountsSummary(),
        calculateAccountWatchlist(basis)
      ]);
    
    const dashboardData = {
      receivables,
      payables,
      cashFlow, // Now includes monthlyData array with 'balance' field
      incomeExpense, // Now includes monthlyData array
      projects,
      bankAccounts,
      watchlist,
      generatedAt: new Date()
    };
    
    console.log('✅ Dashboard summary calculated successfully');
    console.log('📊'.repeat(50) + '\n');
    
    res.json({
      success: true,
      data: dashboardData
    });
    
  } catch (error) {
    console.error('❌ Error generating dashboard summary:', error);
    res.status(500).json({
      success: false,
      message: 'Error generating dashboard summary',
      error: error.message
    });
  }
});

/**
 * GET /api/dashboard/receivables
 */
router.get('/receivables', async (req, res) => {
  try {
    const receivables = await calculateReceivables();
    res.json({ success: true, data: receivables });
  } catch (error) {
    console.error('❌ Error calculating receivables:', error);
    res.status(500).json({
      success: false,
      message: 'Error calculating receivables',
      error: error.message
    });
  }
});

/**
 * GET /api/dashboard/payables
 */
router.get('/payables', async (req, res) => {
  try {
    const payables = await calculatePayables();
    res.json({ success: true, data: payables });
  } catch (error) {
    console.error('❌ Error calculating payables:', error);
    res.status(500).json({
      success: false,
      message: 'Error calculating payables',
      error: error.message
    });
  }
});

/**
 * GET /api/dashboard/cash-flow
 * Returns monthly breakdown for fiscal year WITH cumulative balance
 */
router.get('/cash-flow', async (req, res) => {
  try {
    const { period = 'fiscal_year' } = req.query;
    const cashFlow = await calculateCashFlow(period);
    res.json({ success: true, data: cashFlow });
  } catch (error) {
    console.error('❌ Error calculating cash flow:', error);
    res.status(500).json({
      success: false,
      message: 'Error calculating cash flow',
      error: error.message
    });
  }
});

/**
 * GET /api/dashboard/income-expense
 * Returns monthly breakdown for fiscal year
 * Query params: period, basis (accrual/cash)
 */
router.get('/income-expense', async (req, res) => {
  try {
    const { period = 'fiscal_year', basis = 'accrual' } = req.query;
    const incomeExpense = await calculateIncomeAndExpense(period, basis);
    res.json({ success: true, data: incomeExpense });
  } catch (error) {
    console.error('❌ Error calculating income and expense:', error);
    res.status(500).json({
      success: false,
      message: 'Error calculating income and expense',
      error: error.message
    });
  }
});

/**
 * GET /api/dashboard/projects
 */
router.get('/projects', async (req, res) => {
  try {
    const projects = await calculateProjectsSummary();
    res.json({ success: true, data: projects });
  } catch (error) {
    console.error('❌ Error calculating projects:', error);
    res.status(500).json({
      success: false,
      message: 'Error calculating projects',
      error: error.message
    });
  }
});

/**
 * GET /api/dashboard/bank-accounts
 */
router.get('/bank-accounts', async (req, res) => {
  try {
    const bankAccounts = await calculateBankAccountsSummary();
    res.json({ success: true, data: bankAccounts });
  } catch (error) {
    console.error('❌ Error calculating bank accounts:', error);
    res.status(500).json({
      success: false,
      message: 'Error calculating bank accounts',
      error: error.message
    });
  }
});

/**
 * GET /api/dashboard/watchlist
 */
router.get('/watchlist', async (req, res) => {
  try {
    const { basis = 'accrual' } = req.query;
    const watchlist = await calculateAccountWatchlist(basis);
    res.json({ success: true, data: watchlist });
  } catch (error) {
    console.error('❌ Error calculating watchlist:', error);
    res.status(500).json({
      success: false,
      message: 'Error calculating watchlist',
      error: error.message
    });
  }
});

// ============================================================================
// INCOME/EXPENSE DETAIL REPORT - FOR SPECIFIC MONTH
// ============================================================================

/**
 * GET /api/dashboard/income-expense-detail
 * Get detailed breakdown of income or expense for a specific month
 * Query params: month (e.g., "Jan 2025"), type (income/expense), basis (accrual/cash)
 */
router.get('/income-expense-detail', async (req, res) => {
  try {
    const { month, type, basis = 'accrual' } = req.query;
    
    if (!month || !type) {
      return res.status(400).json({
        success: false,
        message: 'Month and type parameters are required'
      });
    }
    
    console.log(`\n📊 Fetching ${type} detail for ${month} (${basis} basis)...`);
    
    // Parse month string (e.g., "Jan 2025")
    const [monthName, yearStr] = month.split(' ');
    const year = parseInt(yearStr);
    const monthIndex = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].indexOf(monthName);
    
    if (monthIndex === -1) {
      return res.status(400).json({
        success: false,
        message: 'Invalid month format. Use format like "Jan 2025"'
      });
    }
    
    const monthStart = new Date(year, monthIndex, 1);
    const monthEnd = new Date(year, monthIndex + 1, 0);
    
    console.log(`   Period: ${monthStart.toISOString().split('T')[0]} to ${monthEnd.toISOString().split('T')[0]}`);
    
    const db = mongoose.connection.db;
    const transactions = [];
    let totalAmount = 0;
    
    if (type === 'income') {
      if (basis === 'accrual') {
        // Accrual: Based on invoice date
        const invoices = await db.collection('invoices').find({
          invoiceDate: {
            $gte: monthStart,
            $lte: monthEnd
          }
        }).toArray();
        
        console.log(`   Found ${invoices.length} invoices in this month`);
        
        invoices.forEach(invoice => {
          const amount = invoice.totalAmount || 0;
          totalAmount += amount;
          
          transactions.push({
            date: invoice.invoiceDate,
            description: invoice.items && invoice.items.length > 0 
              ? invoice.items[0].description 
              : 'Invoice',
            reference: invoice.invoiceNumber || 'N/A',
            customer: invoice.customerName || invoice.customerId,
            amount: amount
          });
        });
        
      } else {
        // Cash: Based on payment date
        const payments = await db.collection('payments_received').find({
          paymentDate: {
            $gte: monthStart,
            $lte: monthEnd
          },
          status: { $ne: 'void' }
        }).toArray();
        
        console.log(`   Found ${payments.length} payments in this month`);
        
        payments.forEach(payment => {
          const amount = payment.amountReceived || 0;
          totalAmount += amount;
          
          transactions.push({
            date: payment.paymentDate,
            description: payment.notes || 'Payment Received',
            reference: payment.paymentNumber || 'N/A',
            customer: payment.customerName || payment.customerId,
            amount: amount
          });
        });
      }
    } else if (type === 'expense') {
      // TODO: Implement expense tracking when bills/expenses are added
      console.log('   Expense tracking not yet implemented');
    }
    
    // Sort transactions by date (newest first)
    transactions.sort((a, b) => new Date(b.date) - new Date(a.date));
    
    console.log(`   ✅ Total ${type}: ${formatCurrency(totalAmount)}`);
    console.log(`   ✅ Transactions: ${transactions.length}`);
    
    res.json({
      success: true,
      data: {
        month: month,
        type: type,
        basis: basis,
        total_amount: totalAmount,
        transactions: transactions
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching income/expense detail:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching income/expense detail',
      error: error.message
    });
  }
});

module.exports = router;