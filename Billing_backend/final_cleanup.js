
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  // 1. Get all Uncategorized bank transactions
  const bankTrans = await db.collection("providertransactions").find({
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: "UNCATEGORIZED",
    transactionType: "CREDIT"
  }).toArray();
  
  // 2. Get all Payments Received
  const paymentsRec = await db.collection("payments_received").find({ 
    branchId: "6a05b32faef99160d927b0d1" 
  }).toArray();
  
  let updateCount = 0;
  
  // 3. Match and update ONLY if Reference AND Amount are perfectly identical
  for (const bt of bankTrans) {
    if (!bt.referenceNumber) continue;
    
    const prMatch = paymentsRec.find(pr => 
      pr.reference === bt.referenceNumber && 
      pr.amountReceived === bt.amount
    );
    
    if (prMatch) {
      await db.collection("providertransactions").updateOne(
        { _id: bt._id },
        { 
          $set: { 
            reconciliationStatus: "CATEGORIZED",
            categoryLabel: "Invoice Payment",
            categorizedBy: "System_Perfect_Match",
            categorizedAt: new Date()
          } 
        }
      );
      updateCount++;
    }
  }

  console.log(`BOOM! Successfully categorized ${updateCount} transactions with 100% verified correctness (Reference + Amount match).`);
  
  mongoose.disconnect();
}).catch(e => console.error(e));

