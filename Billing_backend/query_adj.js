const mongoose = require('mongoose');
mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const db = mongoose.connection.db;
    
    // Convert branchId string to ObjectId if necessary, but branchId in this system is sometimes stored as ObjectId and sometimes as String.
    // We'll search by ObjectId because '6a05b32faef99160d927b0d1' is a 24 char hex.
    const branchIdObj = new mongoose.Types.ObjectId('6a05b32faef99160d927b0d1');
    const branchIdStr = '6a05b32faef99160d927b0d1';

    // Invoices
    const invoices = await db.collection('invoices').find({
      $or: [{ branchId: branchIdObj }, { branchId: branchIdStr }],
      adjustment: { $exists: true, $ne: 0, $ne: null }
    }).toArray();

    // Credit Notes
    const creditNotes = await db.collection('creditnotes').find({
      $or: [{ branchId: branchIdObj }, { branchId: branchIdStr }],
      adjustment: { $exists: true, $ne: 0, $ne: null }
    }).toArray();

    let totalInvAdj = 0;
    console.log('--- INVOICES WITH ADJUSTMENTS ---');
    if (invoices.length === 0) console.log('None found.');
    invoices.forEach(inv => {
      console.log(`Invoice ${inv.invoiceNumber}: ${inv.adjustment}`);
      totalInvAdj += inv.adjustment;
    });

    let totalCnAdj = 0;
    console.log('\n--- CREDIT NOTES WITH ADJUSTMENTS ---');
    if (creditNotes.length === 0) console.log('None found.');
    creditNotes.forEach(cn => {
      console.log(`Credit Note ${cn.creditNoteNumber || cn._id}: ${cn.adjustment}`);
      totalCnAdj += cn.adjustment;
    });

    console.log('\nTotal Invoice Adjustments:', totalInvAdj);
    console.log('Total Credit Note Adjustments:', totalCnAdj);
    
    process.exit(0);
  })
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
