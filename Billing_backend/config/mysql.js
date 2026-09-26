// config/mysql.js
const mysql = require('mysql2/promise');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const pool = mysql.createPool({
  host: process.env.MYSQL_HOST || 'localhost',
  user: process.env.MYSQL_USER || 'royaldxd_user',
  password: process.env.MYSQL_PASSWORD || 'meg_layout312',
  database: process.env.MYSQL_DATABASE || 'royaldxd_abra_crm',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  charset: 'utf8mb4'
});

// Auto-migration on startup: Ensure the multi-tenant columns exist 
// on the shared PHP CRM database tables so Node.js can use them.
async function initMySQLSchema() {
  try {
    const connection = await pool.getConnection();
    
    // Check if finance_digital_expenses exists
    const [tables] = await connection.query(`SHOW TABLES LIKE 'finance_digital_expenses'`);
    if (tables.length > 0) {
      const [columns] = await connection.query(`SHOW COLUMNS FROM finance_digital_expenses`);
      const colNames = columns.map(c => c.Field);
      if (!colNames.includes('orgId')) {
        await connection.query(`ALTER TABLE finance_digital_expenses ADD COLUMN orgId VARCHAR(255) DEFAULT NULL, ADD INDEX idx_orgId (orgId)`);
      }
      if (!colNames.includes('branchId')) {
        await connection.query(`ALTER TABLE finance_digital_expenses ADD COLUMN branchId VARCHAR(255) DEFAULT NULL, ADD INDEX idx_branchId (branchId)`);
      }
    }

    // Check categories table
    const [catTables] = await connection.query(`SHOW TABLES LIKE 'finance_digital_expense_categories'`);
    if (catTables.length > 0) {
      const [catCols] = await connection.query(`SHOW COLUMNS FROM finance_digital_expense_categories`);
      const catColNames = catCols.map(c => c.Field);
      if (!catColNames.includes('orgId')) {
        await connection.query(`ALTER TABLE finance_digital_expense_categories ADD COLUMN orgId VARCHAR(255) DEFAULT NULL, ADD INDEX idx_orgId (orgId)`);
      }
      if (!catColNames.includes('branchId')) {
        await connection.query(`ALTER TABLE finance_digital_expense_categories ADD COLUMN branchId VARCHAR(255) DEFAULT NULL, ADD INDEX idx_branchId (branchId)`);
      }
    }

    // Check history table
    const [histTables] = await connection.query(`SHOW TABLES LIKE 'finance_digital_expense_history'`);
    if (histTables.length > 0) {
      const [histCols] = await connection.query(`SHOW COLUMNS FROM finance_digital_expense_history`);
      const histColNames = histCols.map(c => c.Field);
      if (!histColNames.includes('orgId')) {
        await connection.query(`ALTER TABLE finance_digital_expense_history ADD COLUMN orgId VARCHAR(255) DEFAULT NULL, ADD INDEX idx_orgId (orgId)`);
      }
      if (!histColNames.includes('branchId')) {
        await connection.query(`ALTER TABLE finance_digital_expense_history ADD COLUMN branchId VARCHAR(255) DEFAULT NULL, ADD INDEX idx_branchId (branchId)`);
      }
    }

    connection.release();
    console.log('✅ MySQL schema synchronized for digital expenses');
  } catch (error) {
    console.error('❌ Error synchronizing MySQL schema:', error.message);
  }
}

// Call auto-migration
initMySQLSchema();

module.exports = pool;
