const mongoose = require('mongoose');

async function checkDb() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  
  const PaymentReceived = mongoose.connection.collection('payments_received');
  
  // Find a payment received that has paymentNumber = 'REC000008' or similar, or just the most recent one.
  const prs = await PaymentReceived.find({}).sort({ _id: -1 }).limit(1).toArray();
  console.log('Most recent PaymentReceived:', prs[0]);

  process.exit(0);
}

checkDb().catch(console.error);
