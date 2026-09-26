const mongoose = require('mongoose');

const uri = "mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority";

async function run() {
  await mongoose.connect(uri);
  const db = mongoose.connection.db;
  
  console.log("Checking ProviderTransaction...");
  const txns = await db.collection('providertransactions').find({
    categoryLabel: "Rent expenses"
  }).toArray();
  
  console.log("Found ProviderTransactions with categoryLabel 'Rent expenses':", txns.length);
  if (txns.length > 0) {
    console.log("Sample:", JSON.stringify(txns[0], null, 2));
  } else {
    // try case-insensitive or without exact match
    const txns2 = await db.collection('providertransactions').find({
      categoryLabel: /rent/i
    }).toArray();
    console.log("Found ProviderTransactions with regex 'rent':", txns2.length);
    if (txns2.length > 0) {
      console.log("Sample:", JSON.stringify(txns2[0].categoryLabel));
    }
  }
  
  console.log("\nChecking ChartOfAccount for Rent expenses...");
  const coa = await db.collection('chartofaccounts').findOne({ accountName: "Rent expenses" });
  if (coa) {
    console.log("Found COA:", coa._id);
    const atxns = await db.collection('accounttransactions').find({ accountId: coa._id }).toArray();
    console.log("Found AccountTransactions:", atxns.length);
    if (atxns.length > 0) {
      console.log("Total Amount:", atxns.reduce((s, t) => s + (t.debit || 0) - (t.credit || 0), 0));
      console.log("Sample:", JSON.stringify(atxns[0], null, 2));
    }
  } else {
    console.log("COA 'Rent expenses' not found.");
  }
  
  mongoose.disconnect();
}

run().catch(console.error);
