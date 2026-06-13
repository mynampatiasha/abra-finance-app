const mongoose = require('mongoose');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function cleanupDrafts() {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('Connected to MongoDB for Draft Cleanup...');

    const db = mongoose.connection.db;
    
    // Find all invoices where status is DRAFT
    const draftInvoices = await db.collection('invoices').find({ status: 'DRAFT' }).toArray();
    console.log(`Found ${draftInvoices.length} DRAFT invoices.`);

    const draftIds = draftInvoices.map(inv => inv._id);

    if (draftIds.length > 0) {
      // Delete AccountTransaction entries linked to these draft invoices
      const result = await db.collection('accounttransactions').deleteMany({
        referenceType: 'Invoice',
        referenceId: { $in: draftIds }
      });
      console.log(`Successfully deleted ${result.deletedCount} invalid AccountTransaction entries linked to DRAFT invoices.`);
    } else {
      console.log('No DRAFT invoices found. Nothing to clean up.');
    }

    console.log('Cleanup complete!');
    process.exit(0);
  } catch (error) {
    console.error('Cleanup failed:', error);
    process.exit(1);
  }
}

cleanupDrafts();
