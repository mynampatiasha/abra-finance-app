const mongoose = require('mongoose');
const { getEffectiveOrgData } = require('./routes/branches');

// Define schema exactly as in digital_expenses.js
const digitalExpenseSchema = new mongoose.Schema({
  voucherNumber: { type: String, required: true },
  orgId: { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null },
  status: { type: String }
}, { collection: 'digitalexpenses' });

const DigitalExpense = mongoose.models.DigitalExpense || mongoose.model('DigitalExpense', digitalExpenseSchema);

async function run() {
  await mongoose.connect(
    'mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority',
    { dbName: 'abra_finance_module' }
  );
  
  const expenses = await DigitalExpense.find({});
  require('fs').writeFileSync('C:/Users/user/debug_dump.json', JSON.stringify(expenses, null, 2));
  console.log("Dumped", expenses.length, "expenses");
  
  process.exit(0);
}

run();
