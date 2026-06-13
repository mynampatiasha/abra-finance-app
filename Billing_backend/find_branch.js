const mongoose = require('mongoose');
const dotenv = require('dotenv');

dotenv.config();

const branchSchema = new mongoose.Schema({ name: String, organization: mongoose.Schema.Types.ObjectId }, { collection: 'branches' });
const Branch = mongoose.model('Branch', branchSchema);

async function run() {
  await mongoose.connect(process.env.MONGODB_URI);
  const branches = await Branch.find({});
  branches.forEach(b => console.log(`ID: ${b._id}, Name: ${b.name}`));
  mongoose.disconnect();
}

run();
