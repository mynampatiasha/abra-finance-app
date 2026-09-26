const mongoose = require('mongoose');

async function checkDb() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  
  const PaymentReceived = mongoose.connection.collection('payments_received');
  
  const linkedObjId = new mongoose.Types.ObjectId('6a5478479eae9bac7e7a70b1');
  const orgId = '6a05b2c6aef99160d927b0bf';
  
  const modelQuery = { _id: linkedObjId, orgId: orgId };
  console.log('Testing query:', modelQuery);
  
  const payment = await PaymentReceived.findOne(modelQuery);
  console.log('Result:', payment);

  process.exit(0);
}

checkDb().catch(console.error);
