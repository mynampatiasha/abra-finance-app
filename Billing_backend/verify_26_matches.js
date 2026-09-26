
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  // Get the transactions that I just updated
  const fixedTrans = await db.collection("providertransactions").find({
    branchId: "6a05b32faef99160d927b0d1",
    categorizedBy: "System_Auto_Fix_Refs"
  }).toArray();
  
  const invoices = await db.collection("invoices").find({ branchId: "6a05b32faef99160d927b0d1" }).toArray();
  
  console.log(`Found ${fixedTrans.length} transactions updated by the script.\n`);
  
  fixedTrans.forEach(t => {
    // Find the matching invoice and payment
    let matchInv = null;
    let matchPay = null;
    
    invoices.forEach(inv => {
      if (inv.payments) {
        inv.payments.forEach(p => {
          if (p.referenceNumber === t.referenceNumber) {
            matchInv = inv;
            matchPay = p;
          }
        });
      }
    });
    
    if (matchInv && matchPay) {
      console.log(`Reference: ${t.referenceNumber}`);
      console.log(`  BANK FEED: Amount: ?${t.amount} | Date: ${new Date(t.transactionDate).toISOString().split("T")[0]}`);
      console.log(`  INVOICE:   Amount: ?${matchPay.amount} | Date: ${new Date(matchPay.paymentDate).toISOString().split("T")[0]} | Customer: ${matchInv.customerName}`);
      
      const amountMatch = t.amount === matchPay.amount ? "?" : "?";
      // dates might differ by 1 day due to timezone or processing delays
      console.log(`  -> Amount Match: ${amountMatch}\n`);
    }
  });

  mongoose.disconnect();
}).catch(e => console.error(e));

