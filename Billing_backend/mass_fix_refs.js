
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  // 1. Get all invoices for this branch
  const invoices = await db.collection("invoices").find({ branchId: "6a05b32faef99160d927b0d1" }).toArray();
  
  // 2. Extract every single reference number from every recorded payment
  const recordedReferences = new Set();
  invoices.forEach(inv => {
    if (inv.payments && Array.isArray(inv.payments)) {
      inv.payments.forEach(p => {
        if (p.referenceNumber) {
          recordedReferences.add(p.referenceNumber.trim());
        }
      });
    }
  });

  const refsArray = Array.from(recordedReferences);
  console.log(`Found ${refsArray.length} unique payment references recorded on invoices.`);

  // 3. Find and fix all UNCATEGORIZED bank feed transactions that match these references
  const result = await db.collection("providertransactions").updateMany(
    { 
      branchId: "6a05b32faef99160d927b0d1",
      reconciliationStatus: "UNCATEGORIZED",
      referenceNumber: { $in: refsArray }
    },
    { 
      $set: { 
        reconciliationStatus: "CATEGORIZED",
        categoryLabel: "Invoice Payment",
        categorizedBy: "System_Auto_Fix_Refs",
        categorizedAt: new Date()
      } 
    }
  );

  console.log(`BOOM! Successfully categorized ${result.modifiedCount} duplicate bank feed transactions based on reference numbers!`);
  
  mongoose.disconnect();
}).catch(e => console.error(e));

