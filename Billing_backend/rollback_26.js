
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const result = await db.collection("providertransactions").updateMany(
    { 
      branchId: "6a05b32faef99160d927b0d1",
      categorizedBy: "System_Auto_Fix_Refs"
    },
    { 
      $set: { 
        reconciliationStatus: "UNCATEGORIZED",
        categoryLabel: null
      },
      $unset: {
        categorizedBy: "",
        categorizedAt: ""
      }
    }
  );

  console.log(`Rolled back ${result.modifiedCount} transactions to UNCATEGORIZED.`);
  
  mongoose.disconnect();
}).catch(e => console.error(e));

