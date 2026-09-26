const jwt = require('./middleware/finance_jwt');
const token = jwt.generateFinanceToken({ _id: 'fake', orgId: '6a05b32faef99160d927b0d1', name: 'tester', email: 'test@test.com' });
console.log('TOKEN:', token);
