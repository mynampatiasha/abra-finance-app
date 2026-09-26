
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const categorizedCount = await db.collection("providertransactions").countDocuments({ 
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: { $in: ["CATEGORIZED", "RECONCILED"] }
  });
  
  console.log("Categorized Transactions: " + categorizedCount);

  const matchedCount = await db.collection("providertransactions").countDocuments({ 
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: "MATCHED"
  });
  
  console.log("Matched Transactions: " + matchedCount);
  
  const uncategorizedCount = await db.collection("providertransactions").countDocuments({ 
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: "UNCATEGORIZED"
  });
  
  console.log("Uncategorized Transactions: " + uncategorizedCount);

  mongoose.disconnect();
}).catch(e => console.error(e));

