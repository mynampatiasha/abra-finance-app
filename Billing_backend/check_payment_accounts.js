const mongoose = require('mongoose');

async function main() {
    const uri = 'mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority';
    await mongoose.connect(uri);

    const db = mongoose.connection.db;
    const branchId = '6a05b32faef99160d927b0d1';

    console.log("--- Payment Accounts ---");
    const accounts = await db.collection('paymentaccounts').find({ branchId }).toArray();
    accounts.forEach(acc => {
        console.log(`Name: ${acc.accountName}, Type: ${acc.accountType}, Balance: ${acc.balance || acc.currentBalance}`);
        if(acc.accountName.toLowerCase().includes('hdfc')) {
            console.log(acc);
        }
    });

    mongoose.disconnect();
}

main().catch(console.error);
