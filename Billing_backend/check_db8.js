const mongoose = require('mongoose');

async function checkDb() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  
  const ProviderTransaction = mongoose.connection.collection('providertransactions');
  const pt = await ProviderTransaction.findOne({ _id: new mongoose.Types.ObjectId('6a5468159eae9bac7e7a6408') });
  
  console.log('ProviderTransaction from payment.providerTransactionId:', pt);

  process.exit(0);
}

checkDb().catch(console.error);
