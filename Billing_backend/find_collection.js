
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  const collections = await db.listCollections().toArray();
  
  for (const col of collections) {
    const doc = await db.collection(col.name).findOne({ paymentNumber: "REC000063" });
    if (doc) {
      console.log(`FOUND IN COLLECTION: ${col.name}`);
      console.log(JSON.stringify(doc, null, 2));
      break;
    }
  }

  mongoose.disconnect();
}).catch(e => console.error(e));

