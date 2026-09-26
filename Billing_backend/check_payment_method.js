
const mongoose = require("mongoose");
const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";
mongoose.connect(uri).then(async () => {
  const db = mongoose.connection.db;
  
  // Look at some PAID invoices
  const paidInvoices = await db.collection("invoices").find({ branchId: "6a05b32faef99160d927b0d1", status: "PAID" }).limit(5).toArray();
  
  console.log("--- SAMPLE PAID INVOICES ---");
  paidInvoices.forEach(inv => {
    console.log(`Invoice: ${inv.invoiceNumber} | Total: ${inv.totalAmount} | Payments Array Length: ${inv.payments ? inv.payments.length : 0}`);
    if (inv.payments && inv.payments.length > 0) {
      console.log(`   First Payment Method: ${inv.payments[0].paymentMode} | Ref: ${inv.payments[0].referenceNumber}`);
    }
  });

  // Look at successfully categorized ProviderTransactions
  const categorizedTrans = await db.collection("providertransactions").find({
    branchId: "6a05b32faef99160d927b0d1",
    reconciliationStatus: { $in: ["CATEGORIZED", "RECONCILED"] }
  }).limit(5).toArray();

  console.log("\n--- SAMPLE CATEGORIZED BANK TRANSACTIONS ---");
  categorizedTrans.forEach(t => {
    console.log(`Trans ID: ${t._id} | Type: ${t.transactionType} | Amount: ${t.amount}`);
    console.log(`   Category: ${t.categoryLabel} | By: ${t.categorizedBy || t.reconciledBy || "unknown"}`);
  });

  mongoose.disconnect();
}).catch(e => console.error(e));

