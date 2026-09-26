require('dotenv').config();
const jwt = require('jsonwebtoken');
const { MongoClient, ObjectId } = require('mongodb');
const ORG = '6a05b2c6aef99160d927b0bf';
const FINANCE_SECRET = process.env.JWT_FINANCE_SECRET || 'abra_finance_super_secret_key_2024';
(async () => {
  const client = new MongoClient(process.env.MONGODB_URI);
  await client.connect();
  const db = client.db();
  // find a real admin/owner user in this org to impersonate for a read-only test token
  const user = await db.collection('billing_users').findOne({});
  console.log('Using sample user for token:', user ? user.email : 'NONE FOUND');
  const token = jwt.sign(
    { userId: (user?._id || new ObjectId()).toString(), email: user?.email || 'test@test.com', name: user?.name || 'Test', role: 'admin', orgId: ORG, orgName: 'Abra E-Logistic Private Limited', permissions: {}, collectionName: 'billing_users' },
    FINANCE_SECRET,
    { expiresIn: '10m', issuer: 'abra_finance_system', algorithm: 'HS256' }
  );
  require('fs').writeFileSync('_tmp_token.txt', token);
  console.log('Token written to _tmp_token.txt');
  await client.close();
})().catch(e => { console.error(e); process.exit(1); });
