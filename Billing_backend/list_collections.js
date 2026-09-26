const mongoose = require('mongoose');
const { connectFinanceDB } = require('./config/database');
require('dotenv').config();

connectFinanceDB().then(async () => {
  try {
    const collections = await mongoose.connection.db.listCollections().toArray();
    console.log('Collections containing payment:');
    collections.filter(c => c.name.toLowerCase().includes('payment')).forEach(c => console.log(' - ' + c.name));
  } catch(e) {
    console.error('Error:', e);
  } finally {
    process.exit(0);
  }
});
