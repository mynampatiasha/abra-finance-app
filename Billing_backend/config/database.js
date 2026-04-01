// config/database.js
// Connects to abra_finance_module database (separate from fleet DB)

const mongoose = require('mongoose');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

let financeDb = null;

async function connectFinanceDB() {
  try {
    console.log('\n🔄 CONNECTING TO abra_finance_module DATABASE');
    console.log('═'.repeat(60));

    mongoose.set('strictQuery', false);
    mongoose.set('bufferCommands', false);

    const options = {
      maxPoolSize: 10,
      minPoolSize: 2,
      serverSelectionTimeoutMS: 30000,
      socketTimeoutMS: 45000,
      connectTimeoutMS: 30000,
      family: 4,
      dbName: 'abra_finance_module', // ← force specific DB
    };

    await mongoose.connect(process.env.MONGODB_URI, options);

    // Wait for db object
    let attempts = 0;
    while (!mongoose.connection.db && attempts < 100) {
      await new Promise(r => setTimeout(r, 500));
      attempts++;
    }

    if (!mongoose.connection.db) throw new Error('DB object not ready');

    financeDb = mongoose.connection.db;

    const stats = await financeDb.stats();
    console.log(`✅ Connected to database: ${stats.db}`);
    console.log(`   Collections: ${stats.collections}`);
    console.log('═'.repeat(60) + '\n');

    // Ensure indexes
    setImmediate(async () => {
      try {
        await financeDb.collection('billing_users').createIndex({ email: 1 }, { unique: true });
        await financeDb.collection('billing_users').createIndex({ 'organizations.orgId': 1 });
        await financeDb.collection('organizations').createIndex({ ownerId: 1 });
        console.log('✅ Finance DB indexes created');
      } catch (e) {
        console.warn('⚠️  Index warning:', e.message);
      }
    });

    return financeDb;
  } catch (error) {
    console.error('❌ Finance DB connection failed:', error.message);
    throw error;
  }
}

function getFinanceDb() {
  if (!financeDb) throw new Error('Finance DB not initialized. Call connectFinanceDB() first.');
  return financeDb;
}

module.exports = { connectFinanceDB, getFinanceDb };
