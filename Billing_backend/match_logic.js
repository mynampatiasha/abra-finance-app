
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
  
  console.log("Found " + trans.length + " UNCATEGORIZED CREDIT transactions.");
  console.log("Found " + invoices.length + " INVOICES.");
  console.log("\n--- MATCHING LOGIC RESULTS ---\n");
  
  let matchCount = 0;
  trans.forEach(t => {
    // Try to find an invoice matching this exact amount
    const matchingInvoices = invoices.filter(inv => Math.abs(inv.totalAmount - t.amount) < 1.0);
    
    if (matchingInvoices.length > 0) {
      matchCount++;
      const inv = matchingInvoices[0]; // just take first match for display
      console.log(`? MATCH FOUND!`);
      console.log(`   Transaction ID: ${t._id}`);
      console.log(`   Trans Amount: ?${t.amount} | Reference: ${t.referenceNumber || "N/A"}`);
      console.log(`   >> Matches Invoice: ${inv.invoiceNumber} | Customer: ${inv.customerName}`);
      console.log(`   >> Invoice Total: ?${inv.totalAmount} | Status: ${inv.status}\n`);
    }
  });

  console.log(`Total exact matches found based on Amount: ${matchCount}`);

  mongoose.disconnect();
}).catch(e => console.error(e));

