require('dotenv').config();
const { MongoClient } = require('mongodb');

async function run() {
  const uri = process.env.MONGODB_URI;
  const client = new MongoClient(uri);
  await client.connect();
  const db = client.db(process.env.FINANCE_DB_NAME || 'abra_finance_module');
  
  // Find the customer that has invoices
  const invoices = await db.collection('invoices').find({ status: { $ne: 'CANCELLED' } }).sort({ invoiceDate: -1 }).limit(10).toArray();
  console.log('Recent invoices:', invoices.map(i => ({ 
    id: i._id, 
    customerName: i.customerName,
    invoiceNumber: i.invoiceNumber,
    status: i.status,
    paymentsCount: (i.payments || []).length,
    payments: i.payments
  })));
  
  // Let's also check recent payments
  const payments = await db.collection('payments_received').find({}).sort({ createdAt: -1 }).limit(5).toArray();
  console.log('Recent payments_received:', payments.map(p => ({
    id: p._id,
    customerName: p.customerName,
    amount: p.amountReceived,
    invoicePayments: p.invoicePayments,
    paymentDate: p.paymentDate
  })));

  await client.close();
}
run().catch(console.error);
