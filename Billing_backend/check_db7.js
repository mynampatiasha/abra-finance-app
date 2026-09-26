const mongoose = require('mongoose');

async function checkDb() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  
  const ProviderTransaction = mongoose.connection.collection('providertransactions');
  const pt1 = await ProviderTransaction.findOne({ _id: new mongoose.Types.ObjectId('6a54678d9eae9bac7e7a49e4') });
  
  console.log('ProviderTransaction from PaymentReceived:', pt1);

  process.exit(0);
}

checkDb().catch(console.error);
