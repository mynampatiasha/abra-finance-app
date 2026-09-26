
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const docs = await db.collection("providertransactions").find({ 
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: "UNCATEGORIZED"
  }).toArray();
  
  console.log("Found " + docs.length + " UNCATEGORIZED transactions for this branch:");
  docs.forEach(d => {
    console.log(`- ID: ${d._id}`);
    console.log(`  Date: ${d.transactionDate}`);
    console.log(`  Amount: ${d.amount} (${d.transactionType})`);
    console.log(`  Description: ${d.description || d.rawData?.Description || "N/A"}`);
    console.log(`  Reference: ${d.referenceNumber || d.rawData?.["Reference Number"] || "N/A"}`);
    console.log(`  Matched Invoice: ${d.matchedInvoiceId || "none"}`);
    console.log("");
  });

  mongoose.disconnect();
}).catch(e => console.error(e));

