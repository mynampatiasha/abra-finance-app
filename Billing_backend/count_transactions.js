const mongoose = require('mongoose');
mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
.then(async () => {
    const db = mongoose.connection.db;
    const branchIdStr = "69eeecb21234dffba797bee4";
    
    let branchIdObj;
    try {
        branchIdObj = new mongoose.Types.ObjectId(branchIdStr);
    } catch(e) {}
    
    const collectionName = 'providertransactions';
    
    const totalBank = await db.collection(collectionName).countDocuments({});
    
    const countBankObj = branchIdObj ? await db.collection(collectionName).countDocuments({ branchId: branchIdObj }) : 0;
    const countBankStr = await db.collection(collectionName).countDocuments({ branchId: branchIdStr });
    
    const countBankObjArray = branchIdObj ? await db.collection(collectionName).countDocuments({ branchIds: branchIdObj }) : 0;
    const countBankStrArray = await db.collection(collectionName).countDocuments({ branchIds: branchIdStr });
    
    console.log(`Total overall in ${collectionName}: ${totalBank}`);
    console.log(`Total for branch (branchId as ObjId): ${countBankObj}`);
    console.log(`Total for branch (branchId as String): ${countBankStr}`);
    console.log(`Total for branch (branchIds array contains ObjId): ${countBankObjArray}`);
    console.log(`Total for branch (branchIds array contains String): ${countBankStrArray}`);
    
    process.exit(0);
});
