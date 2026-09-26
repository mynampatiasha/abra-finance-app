
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const fullyPaidCount = await db.collection("invoices").countDocuments({ 
    branchId: "6a05b32faef99160d927b0d1",
    status: "PAID"
  });

  const partialPaidCount = await db.collection("invoices").countDocuments({ 
    branchId: "6a05b32faef99160d927b0d1",
    status: "PARTIALLY_PAID"
  });

  const allInvoices = await db.collection("invoices").countDocuments({ 
    branchId: "6a05b32faef99160d927b0d1"
  });

  console.log("Fully PAID Invoices: " + fullyPaidCount);
  console.log("PARTIALLY_PAID Invoices: " + partialPaidCount);
  console.log("Total Invoices (all statuses): " + allInvoices);

  mongoose.disconnect();
}).catch(e => console.error(e));

