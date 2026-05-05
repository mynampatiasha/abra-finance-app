// middleware/finance_jwt.js
// Separate JWT middleware for finance module — uses JWT_FINANCE_SECRET

const jwt = require('jsonwebtoken');
const { ObjectId } = require('mongodb');

const FINANCE_SECRET = process.env.JWT_FINANCE_SECRET || 'abra_finance_super_secret_key_2024';
const FINANCE_EXPIRES = process.env.JWT_FINANCE_EXPIRES_IN || '24h';

// ─── Generate finance-scoped token ───────────────────────────────────────────
const generateFinanceToken = (user, org) => {
  return jwt.sign(
    {
      userId:         user._id.toString(),
      email:          user.email,
      name:           user.name,
      phone:          user.phone || '',
      role:           org ? org.role : user.role,
      orgId:          org ? org.orgId : null,
      orgName:        org ? org.orgName : null,
      permissions:    user.permissions || {},
      collectionName: 'billing_users',
    },
    FINANCE_SECRET,
    { expiresIn: FINANCE_EXPIRES, issuer: 'abra_finance_system', algorithm: 'HS256' }
  );
};

// ─── Verify middleware ────────────────────────────────────────────────────────
const verifyFinanceJWT = async (req, res, next) => {
  try {
    // Support token from query param (e.g. PDF download links: ?token=...)
    let token = req.query.token;

    if (!token) {
      const authHeader = req?.headers?.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ success: false, error: 'No token provided', code: 'MISSING_TOKEN' });
      }
      token = authHeader.split('Bearer ')[1];
    }

    if (!token) {
      return res.status(401).json({ success: false, error: 'Invalid token format', code: 'INVALID_FORMAT' });
    }

    const decoded = jwt.verify(token, FINANCE_SECRET, { algorithms: ['HS256'] });

    req.user = {
      userId:      decoded.userId,
      email:       decoded.email,
      name:        decoded.name,
      phone:       decoded.phone,
      role:        decoded.role,
      orgId:       decoded.orgId,
      orgName:     decoded.orgName,
      permissions: decoded.permissions || {},
    };

    if (!req.user.userId || !req.user.email) {
      return res.status(401).json({ success: false, error: 'Incomplete token', code: 'INCOMPLETE_TOKEN' });
    }

    // Verify user exists and is active in billing_users
    if (req.db) {
      const user = await req.db.collection('billing_users').findOne({
        _id: new ObjectId(req.user.userId),
      });
      if (!user) {
        return res.status(401).json({ success: false, error: 'User not found', code: 'USER_NOT_FOUND' });
      }
      if (user.status !== 'active') {
        return res.status(403).json({ success: false, error: 'Account inactive', code: 'ACCOUNT_INACTIVE' });
      }
      // refresh permissions from DB (always latest)
      req.user.permissions = user.permissions || {};
    }

    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, error: 'Token expired', code: 'TOKEN_EXPIRED' });
    }
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, error: 'Invalid token', code: 'INVALID_TOKEN' });
    }
    return res.status(401).json({ success: false, error: 'Auth failed', code: 'AUTH_FAILED' });
  }
};

// ─── Owner/Admin guard ────────────────────────────────────────────────────────
const requireOwnerOrAdmin = (req, res, next) => {
  const role = req.user?.role;
  if (role === 'owner' || role === 'admin') return next();
  return res.status(403).json({
    success: false,
    error: 'Access denied. Owner or Admin role required.',
    code: 'INSUFFICIENT_ROLE',
  });
};

module.exports = { generateFinanceToken, verifyFinanceJWT, requireOwnerOrAdmin };
