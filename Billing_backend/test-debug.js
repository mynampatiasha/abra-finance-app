const mongoose = require('mongoose');
const uri = 'mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority';

async function test() {
  await mongoose.connect(uri);
  const PaymentReceived = mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'payments_received');
  
  const unusedPayments = await PaymentReceived.find({
    amountInExcess: { $gt: 0 }
  }).select('_id paymentNumber paymentDate amountInExcess paymentMode').sort({ paymentDate: -1 }).lean();
  
  console.log('Unused Payments:', unusedPayments);
  process.exit(0);
}
test().catch(e => { console.error(e); process.exit(1); });
