
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  // Get all Uncategorized bank transactions
  const bankTrans = await db.collection("providertransactions").find({
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: "UNCATEGORIZED",
    transactionType: "CREDIT"
  }).toArray();
  
  // Get all Payments Received
  const paymentsRec = await db.collection("payments_received").find({ 
    branchId: "6a05b32faef99160d927b0d1" 
  }).toArray();
  
  let matchCount = 0;
  
  console.log("--- EXACT MATCHES BETWEEN BANK FEED & PAYMENTS RECEIVED ---\n");
  
  for (const bt of bankTrans) {
    if (!bt.referenceNumber) continue;
    
    // Find matching payment received by reference
    const prMatch = paymentsRec.find(pr => pr.reference === bt.referenceNumber);
    
    if (prMatch) {
      matchCount++;
      const bDate = new Date(bt.transactionDate);
      const bDateStr = `${String(bDate.getDate()).padStart(2, "0")}/${String(bDate.getMonth()+1).padStart(2, "0")}/${bDate.getFullYear()}`;
      
      console.log(`Reference: ${bt.referenceNumber}`);
      console.log(`  BANK FEED: Amount: ?${bt.amount} | Date: ${bDateStr} | Payee: ${bt.description || bt.rawData?.Description || "N/A"}`);
      console.log(`  PAYMENTS : Amount: ?${prMatch.amountReceived} | Date: ${prMatch.paymentDate} | Customer: ${prMatch.customerName}`);
      
      const amountMatch = (bt.amount === prMatch.amountReceived) ? "MATCH ?" : "MISMATCH ?";
      console.log(`  -> Amount Check: ${amountMatch}\n`);
    }
  }

  console.log(`Total exact matches found on Reference Number: ${matchCount}`);
  
  mongoose.disconnect();
}).catch(e => console.error(e));

