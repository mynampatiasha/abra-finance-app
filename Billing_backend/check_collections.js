const mongoose = require('mongoose');
const { connectFinanceDB } = require('./config/database');
require('dotenv').config();

connectFinanceDB().then(async () => {
  try {
    const PaymentsReceived = mongoose.connection.db.collection('payments_received');
    const paymentreceived = mongoose.connection.db.collection('paymentreceived');
    
    const count1 = await PaymentsReceived.countDocuments();
    const count2 = await paymentreceived.countDocuments();
    
    console.log(`Count in 'payments_received': ${count1}`);
    console.log(`Count in 'paymentreceived': ${count2}`);
    
    const branchId = '6a05b32faef99160d927b0d1';
    
    const bCount1 = await PaymentsReceived.countDocuments({ branchId });
    const bCount2 = await paymentreceived.countDocuments({ branchId });
    
    console.log(`Count for branch in 'payments_received': ${bCount1}`);
    console.log(`Count for branch in 'paymentreceived': ${bCount2}`);
    
  } catch(e) {
    console.error('Error:', e);
  } finally {
    process.exit(0);
  }
});
