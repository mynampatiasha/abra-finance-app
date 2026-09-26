
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  const inv = await db.collection("invoices").findOne({ invoiceNumber: "INV000016" });
  
  if (inv && inv.payments) {
    console.log(`Invoice: ${inv.invoiceNumber} | Total: ${inv.totalAmount} | Paid: ${inv.amountPaid}`);
    console.log("--- PAYMENTS ON THIS INVOICE ---");
    inv.payments.forEach(p => {
      console.log(`Payment Date: ${p.paymentDate} | Amount: ${p.amount} | Ref: ${p.referenceNumber}`);
    });
  } else {
    console.log("Invoice not found or has no payments.");
  }

  mongoose.disconnect();
}).catch(e => console.error(e));

