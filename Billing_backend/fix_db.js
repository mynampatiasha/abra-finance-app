
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const trans = await db.collection("providertransactions").find({ 
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: "UNCATEGORIZED",
    transactionType: "CREDIT"
  }).toArray();
  
  const invoices = await db.collection("invoices").find({
    branchId: "6a05b32faef99160d927b0d1"
  }).toArray();
  
  let updateCount = 0;
  
  for (const t of trans) {
    const matchingInvoices = invoices.filter(inv => Math.abs(inv.totalAmount - t.amount) < 1.0);
    
    if (matchingInvoices.length > 0) {
      // We found a match! Update this transaction in the database
      await db.collection("providertransactions").updateOne(
        { _id: t._id },
        { 
          $set: { 
            reconciliationStatus: "CATEGORIZED",
            categoryLabel: "Invoice Payment",
            categorizedBy: "System_Auto_Fix",
            categorizedAt: new Date()
          } 
        }
      );
      updateCount++;
    }
  }

  console.log(`Successfully fixed ${updateCount} Customer Payment transactions in the database!`);
  mongoose.disconnect();
}).catch(e => console.error(e));

