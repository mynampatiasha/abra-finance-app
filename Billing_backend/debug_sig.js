const mongoose = require('mongoose');
const { getEffectiveOrgData } = require('./routes/branches');


async function check() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  const db = mongoose.connection.db;
  
  // Find DE0002
  const expense = await db.collection('digitalexpenses').findOne({ voucherNumber: 'DE0002' });
  console.log("Expense:", expense ? { voucherNumber: expense.voucherNumber, orgId: expense.orgId, status: expense.status } : 'Not found');
  
  if (expense) {
    const orgData = await getEffectiveOrgData(expense.orgId, expense.branchId, db);
    console.log("orgData:", orgData ? { orgName: orgData.orgName, digitalSignaturePath: orgData.digitalSignaturePath } : 'Not found');
    
    if (orgData && orgData.digitalSignaturePath) {
      const path = require('path');
      const fs = require('fs');
      const sigAbsPath = path.join(process.cwd(), orgData.digitalSignaturePath.replace(/^\//, ''));
      console.log("sigAbsPath:", sigAbsPath);
      console.log("exists:", fs.existsSync(sigAbsPath));
    }
  }
  process.exit(0);
}
check();
