
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const inv = await db.collection("invoices").find().sort({_id:-1}).limit(2).toArray();
  console.log("--- INVOICE SCHEMA ---");
  console.log(inv.length ? JSON.stringify(inv, null, 2) : "no invoices");

  const cp = await db.collection("customerpayments").find().sort({_id:-1}).limit(2).toArray();
  console.log("\n--- CUSTOMER PAYMENT SCHEMA ---");
  console.log(cp.length ? JSON.stringify(cp, null, 2) : "no customer payments");

  mongoose.disconnect();
}).catch(e => console.error(e));

