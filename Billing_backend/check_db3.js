const mongoose = require('mongoose');
const uri = 'mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority';
mongoose.connect(uri).then(async () => {
  const CreditNote = mongoose.connection.collection('credit-notes');
  const cn = await CreditNote.findOne({ creditNoteNumber: 'CN000006' });
  console.log('CN000006 doc:', cn);
  process.exit(0);
}).catch(err => {
  console.error(err);
  process.exit(1);
});
