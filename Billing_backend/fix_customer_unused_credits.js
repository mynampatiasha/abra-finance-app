// ============================================================================
// ONE-TIME SCRIPT: Fix Customer unusedCredits from Existing Credit Notes
// ============================================================================
// Run this once to backfill customer unusedCredits from existing credit notes
// Usage: node fix_customer_unused_credits.js
// ============================================================================

const mongoose = require('mongoose');
require('dotenv').config();

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/your_database';

async function fixCustomerUnusedCredits() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(MONGO_URI);
    console.log('✅ Connected to MongoDB');

    // Get models
    const CreditNote = mongoose.models.CreditNote
      || mongoose.model('CreditNote', new mongoose.Schema({}, { strict: false }), 'creditnotes');
    
    const Customer = mongoose.models.BillingCustomer
      || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');

    // Get all credit notes
    const creditNotes = await CreditNote.find({}).lean();
    console.log(`📋 Found ${creditNotes.length} credit notes`);

    // Group by customer and calculate total unused credits
    const customerCredits = {};
    
    for (const cn of creditNotes) {
      const customerId = cn.customerId?.toString();
      if (!customerId) continue;

      // Calculate unused credit for this credit note
      // creditBalance = totalAmount - (applications + refunds)
      const creditBalance = cn.creditBalance || 0;
      
      if (!customerCredits[customerId]) {
        customerCredits[customerId] = 0;
      }
      customerCredits[customerId] += creditBalance;
      
      console.log(`  CN ${cn.creditNoteNumber}: Customer ${customerId} has ₹${creditBalance} unused`);
    }

    console.log(`\n📊 Summary: ${Object.keys(customerCredits).length} customers with unused credits`);

    // Update each customer
    let updated = 0;
    for (const [customerId, totalUnusedCredits] of Object.entries(customerCredits)) {
      try {
        const customer = await Customer.findById(customerId);
        if (!customer) {
          console.log(`⚠️  Customer ${customerId} not found, skipping`);
          continue;
        }

        const before = customer.unusedCredits || 0;
        customer.unusedCredits = totalUnusedCredits;
        await customer.save();

        console.log(`✅ Updated ${customer.customerDisplayName}: ₹${before} → ₹${totalUnusedCredits}`);
        updated++;
      } catch (err) {
        console.error(`❌ Error updating customer ${customerId}:`, err.message);
      }
    }

    console.log(`\n🎉 Done! Updated ${updated} customers`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await mongoose.disconnect();
    console.log('🔌 Disconnected from MongoDB');
  }
}

// Run the script
fixCustomerUnusedCredits();
