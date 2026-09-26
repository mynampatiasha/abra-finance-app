const mongoose = require('mongoose');

async function fixOrphan() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  
  const PaymentReceived = mongoose.connection.collection('payments_received');
  const Invoice = mongoose.connection.collection('invoices');
  
  const pmt = await PaymentReceived.findOne({ _id: new mongoose.Types.ObjectId('6a5478479eae9bac7e7a70b1') });
  
  if (pmt) {
    console.log('Found orphaned payment, deleting...');
    await PaymentReceived.deleteOne({ _id: pmt._id });
    
    // Revert invoice
    const invId = new mongoose.Types.ObjectId('6a127dddaef99160d927efa9');
    const inv = await Invoice.findOne({ _id: invId });
    if (inv) {
      console.log('Reverting invoice...');
      await Invoice.updateOne(
        { _id: invId },
        { 
          $set: { amountPaid: 0, amountDue: inv.totalAmount, status: 'SENT' },
          $pull: { payments: { paymentId: '6a5478479eae9bac7e7a70b1' } }
        }
      );
    }
  }

  process.exit(0);
}

fixOrphan().catch(console.error);
