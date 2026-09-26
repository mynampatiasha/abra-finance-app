const mongoose = require('mongoose');
const { connectFinanceDB } = require('./config/database');
require('dotenv').config();

connectFinanceDB().then(async () => {
  try {
    const ProviderTransaction = mongoose.models.ProviderTransaction || mongoose.model('ProviderTransaction', new mongoose.Schema({}, { strict: false }), 'providertransactions');
    const PaymentReceived = mongoose.models.PaymentReceived || mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'paymentreceived');
    
    const branchId = '6a05b32faef99160d927b0d1';
    
    // Check for Customer Payments in ProviderTransaction
    const txns = await ProviderTransaction.find({ branchId, reconciliationStatus: 'CATEGORIZED' }).lean();
    console.log(`Found ${txns.length} categorized transactions for this branch.`);
    
    const custPayments = txns.filter(t => t.categoryLabel && t.categoryLabel.toLowerCase().includes('customer'));
    console.log(`\nFound ${custPayments.length} categorized bank transactions mentioning 'Customer'.`);
    
    if (custPayments.length > 0) {
        custPayments.slice(0, 5).forEach(t => {
            console.log(` - ID: ${t._id} | Label: ${t.categoryLabel} | Amount: ${t.amount} | Linked Record ID: ${t.linkedRecordId || 'NONE'} | Linked Record Type: ${t.linkedRecordType || 'NONE'}`);
        });
        
        // Check if these linked records exist in PaymentReceived
        for (let t of custPayments.slice(0, 5)) {
            if (t.linkedRecordId) {
                const p = await PaymentReceived.findById(t.linkedRecordId).lean();
                if (p) {
                    console.log(`   -> FOUND in PaymentReceived! branchId on this payment is: ${p.branchId}`);
                } else {
                    console.log(`   -> NOT FOUND in PaymentReceived (Or saved in a different collection)`);
                }
            }
        }
    }
    
    // Check if PaymentReceived has records with NO branchId or a different branchId
    const allPayments = await PaymentReceived.find({}).limit(5).lean();
    console.log(`\nChecking all PaymentReceived records (sample of 5)...`);
    allPayments.forEach(p => {
        console.log(` - Payment ID: ${p._id} | Amount: ${p.amountReceived} | branchId: ${p.branchId} | providerTxnId: ${p.providerTransactionId}`);
    });

  } catch(e) {
    console.error('Error:', e);
  } finally {
    process.exit(0);
  }
});
