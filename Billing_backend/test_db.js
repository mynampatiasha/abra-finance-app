const mongoose = require('mongoose');
mongoose.connect('mongodb://localhost:27017/abra_finance_dev', { useNewUrlParser: true, useUnifiedTopology: true })
.then(async () => {
    const db = mongoose.connection.db;
    const AccountTransaction = db.collection('accounttransactions');
    const txns = await AccountTransaction.find({}).limit(5).toArray();
    console.log(txns.map(t => ({ refNum: t.referenceNumber, refType: t.referenceType, refId: t.referenceId })));
    process.exit(0);
});
