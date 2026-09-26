const mongoose = require('mongoose');

async function main() {
    const uri = 'mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority';
    await mongoose.connect(uri);

    const db = mongoose.connection.db;

    const idfc = await db.collection('chartofaccounts').find({ accountName: { $regex: /idfc/i }, branchId: '6a05b32faef99160d927b0d1' }).toArray();
    console.log("IDFC accounts:", idfc);

    mongoose.disconnect();
}

main().catch(console.error);
