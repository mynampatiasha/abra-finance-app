const mongoose = require('mongoose');

async function checkDb() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  
  const PaymentReceived = mongoose.connection.collection('payments_received');
  
  const p1 = await PaymentReceived.findOne({ providerTransactionId: new mongoose.Types.ObjectId('6a534c6d8e763e8aa582ee58') });
  const p2 = await PaymentReceived.findOne({ providerTransactionId: '6a534c6d8e763e8aa582ee58' });
  const p3 = await PaymentReceived.findOne({ customerName: { $regex: /liquid/i } });
  
  console.log('By ObjectId:', p1);
  console.log('By String:', p2);
  console.log('By Name:', p3);

  process.exit(0);
}

checkDb().catch(console.error);
