const mongoose = require('mongoose');
const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const backupDir = path.join(__dirname, 'backup_june12');
if (!fs.existsSync(backupDir)) {
  fs.mkdirSync(backupDir);
}

async function backup() {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('Connected to MongoDB');

    const db = mongoose.connection.db;
    
    // Backup Invoices
    const invoices = await db.collection('invoices').find({}).toArray();
    fs.writeFileSync(path.join(backupDir, 'invoices_backup.json'), JSON.stringify(invoices, null, 2));
    console.log(`Backed up ${invoices.length} invoices.`);

    // Backup AccountTransactions
    const transactions = await db.collection('accounttransactions').find({}).toArray();
    fs.writeFileSync(path.join(backupDir, 'accounttransactions_backup.json'), JSON.stringify(transactions, null, 2));
    console.log(`Backed up ${transactions.length} account transactions.`);

    // Backup ChartOfAccounts
    const coa = await db.collection('chartofaccounts').find({}).toArray();
    fs.writeFileSync(path.join(backupDir, 'chartofaccounts_backup.json'), JSON.stringify(coa, null, 2));
    console.log(`Backed up ${coa.length} chart of accounts.`);

    console.log('Backup complete!');
    process.exit(0);
  } catch (error) {
    console.error('Backup failed:', error);
    process.exit(1);
  }
}

backup();
