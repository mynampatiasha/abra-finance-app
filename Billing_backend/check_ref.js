
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const trans = await db.collection("providertransactions").findOne({ 
    branchId: "6a05b32faef99160d927b0d1",
    referenceNumber: "Ref-00037"
  });
  console.log("--- TRANSACTION ---");
  console.log(trans ? `Amount: ${trans.amount} | Ref: ${trans.referenceNumber} | Status: ${trans.reconciliationStatus}` : "Not found");

  const invoices = await db.collection("invoices").find({
    branchId: "6a05b32faef99160d927b0d1",
    $or: [
      { totalAmount: { $gte: 33000, $lte: 34000 } },
      { customerName: { $regex: /INVENTIS/i } }
    ]
  }).toArray();
  
  console.log("\n--- POTENTIAL INVOICE MATCHES ---");
  invoices.forEach(inv => {
    console.log(`Invoice: ${inv.invoiceNumber} | Total: ${inv.totalAmount} | Paid: ${inv.amountPaid} | Due: ${inv.amountDue} | Customer: ${inv.customerName} | Status: ${inv.status}`);
  });

  mongoose.disconnect();
}).catch(e => console.error(e));

