const mongoose = require('mongoose');
mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const orgId = '6a05b2c6aef99160d927b0bf';
    const branchId = '6a05b32faef99160d927b0d1';
    
    // Exact scope from orgScope(req) in finance_jwt.js
    const scope = { orgId, branchId: { $in: [branchId] } };

    const PaymentAccount = mongoose.connection.db.collection('paymentaccounts');
    const paymentAccounts = await PaymentAccount.find({ ...scope }).toArray();
    console.log('PaymentAccounts count with branch filter:', paymentAccounts.length);
    
    process.exit(0);
  });
