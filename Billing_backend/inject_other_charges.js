const mongoose = require('mongoose');

mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const db = mongoose.connection.db;
    
    // We need to insert 'Other Charges' into EVERY unique orgId + branchId combination that currently has a Sales account
    const salesAccounts = await db.collection('chartofaccounts').find({ accountName: 'Sales', isSystemAccount: true }).toArray();
    
    let injected = 0;
    for (const sales of salesAccounts) {
      const exists = await db.collection('chartofaccounts').findOne({
        accountName: 'Other Charges',
        isSystemAccount: true,
        orgId: sales.orgId,
        branchId: sales.branchId
      });
      
      if (!exists) {
        await db.collection('chartofaccounts').insertOne({
          accountCode: '4020',
          accountName: 'Other Charges',
          accountType: 'Income',
          accountSubType: 'Income',
          isSystemAccount: true,
          description: 'Invoice adjustments and rounding off',
          orgId: sales.orgId,
          branchId: sales.branchId,
          isActive: true,
          createdAt: new Date(),
          updatedAt: new Date()
        });
        injected++;
      }
    }
    console.log(`Injected Other Charges account into ${injected} org/branch contexts.`);
    process.exit(0);
  })
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
