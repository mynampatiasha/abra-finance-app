const req = {
  params: { id: '6a0f3699478f7e5b22558661' },
  query: { months: 6 },
  orgFilter: {}
};
const res = {
  status: function(code) { this.code = code; return this; },
  json: function(data) { console.log('JSON:', JSON.stringify(data, null, 2)); return this; }
};

const mongoose = require('mongoose');
const uri = 'mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority';

async function test() {
  await mongoose.connect(uri);
  // register models
  mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
  mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');
  mongoose.model('CreditNote', new mongoose.Schema({}, { strict: false }), 'credit-notes');
  mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'payments_received');

  // require and call the router logic
  const routes = require('./routes/billing-customers.js');
  // wait, getCustomerOverview is not exported.
  // We can just copy the logic here:
  const customer = await mongoose.models.BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
  console.log('Customer:', customer ? 'Found' : 'Not found');
  
  if (!customer) { console.log('Not found'); return; }
  
  const Invoice = mongoose.models.Invoice;
  const CreditNote = mongoose.models.CreditNote;
  const PaymentReceived = mongoose.models.PaymentReceived;
  
  let unpaidInvoicesList = [];
  try {
    unpaidInvoicesList = await Invoice.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
        status: { $in: ['SENT', 'UNPAID', 'PARTIALLY_PAID', 'OVERDUE'] },
        ...req.orgFilter,
      }).select('_id invoiceNumber invoiceDate amountDue').sort({ invoiceDate: -1 }).lean();
      
    console.log('unpaidInvoicesList length:', unpaidInvoicesList.length);
  } catch(e) {
    console.error('Invoice query failed', e);
  }

  try {
    const unusedCreditNotes = await CreditNote.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
        creditBalance: { $gt: 0 },
        status: { $nin: ['VOID', 'DRAFT'] },
        ...req.orgFilter,
      }).select('_id creditNoteNumber creditNoteDate creditBalance').sort({ creditNoteDate: -1 }).lean();
    console.log('unusedCreditNotes length:', unusedCreditNotes.length);
  } catch(e) {
    console.error('CreditNote query failed', e);
  }

  try {
    const unusedPayments = await PaymentReceived.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
        amountInExcess: { $gt: 0 },
        ...req.orgFilter,
      }).select('_id paymentNumber paymentDate amountInExcess paymentMode').sort({ paymentDate: -1 }).lean();
    console.log('unusedPayments length:', unusedPayments.length);
  } catch(e) {
    console.error('Payment query failed', e);
  }

  process.exit(0);
}
test().catch(e => { console.error(e); process.exit(1); });
