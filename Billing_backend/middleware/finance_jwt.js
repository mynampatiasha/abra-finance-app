// middleware/finance_jwt.js
// Separate JWT middleware for finance module — uses JWT_FINANCE_SECRET

const jwt = require('jsonwebtoken');
const { ObjectId } = require('mongodb');

const FINANCE_SECRET = process.env.JWT_FINANCE_SECRET || 'abra_finance_super_secret_key_2024';
const FINANCE_EXPIRES = process.env.JWT_FINANCE_EXPIRES_IN || '3d';

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

    // ─── Organization filter — read selected org IDs from header ─────────────
    // Frontend sends: x-org-ids: "orgId1,orgId2"  OR  "ALL"  OR  single orgId (default)
    // Also accepts ?orgIds= query param for PDF download links
    // req.orgFilter  → spread directly into queries: { ...req.orgFilter, ...req.branchFilter }
    // req.orgIds     → array of selected org IDs
    // BACKWARD COMPATIBLE: If header missing, defaults to current orgId from token
    const orgHeader = req.headers['x-org-ids'] || req.query.orgIds;

    // ─── Branch filter — read selected branch IDs from header ────────────────
    // Frontend sends: x-branch-ids: "branchId1,branchId2"  OR  "ALL"
    // Also accepts ?branchIds= query param for PDF download links
    // req.branchFilter  → spread directly into simple queries: { ...orgFilter, ...req.branchFilter }
    // req.branchIds     → array of selected IDs (empty = ALL)
    // Records with branchId=null are NOT shown in branch-scoped views to prevent data leakage
    const branchHeader = req.headers['x-branch-ids'] || req.query.branchIds;

    // Strict branch enforcement — header (or query param for PDF links) is mandatory
    if (!branchHeader || branchHeader.trim() === '' || branchHeader.trim() === 'undefined' || branchHeader.trim() === 'null') {
      console.error('❌ Missing branch context:', {
        branchHeader,
        headers: req.headers,
        query: req.query,
        path: req.path,
        method: req.method,
      });
      return res.status(400).json({
        success: false,
        error: 'Missing branch context',
        message: 'x-branch-ids header is required. Please select a branch.',
        code: 'MISSING_BRANCH_CONTEXT',
        debug: {
          receivedHeader: branchHeader,
          path: req.path,
        },
      });
    }

    if (branchHeader.trim() === 'ALL') {
      // User selected all branches — org-level scope only (orgId handles isolation)
      req.branchIds    = [];
      req.branchFilter = {};
    } else {
      const ids = branchHeader.split(',').map(s => s.trim()).filter(Boolean);
      if (ids.length === 0) {
        return res.status(400).json({
          success: false,
          error: 'Invalid branch context',
          message: 'x-branch-ids header contains no valid branch IDs.',
          code: 'INVALID_BRANCH_CONTEXT',
        });
      }
      req.branchIds    = ids;
      req.branchFilter = { branchId: { $in: ids } };
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

      // ─── Organization access control ────────────────────────────────────────
      // Validate user has access to requested organizations
      const userOrgIds = (user.organizations || []).map(o => o.orgId);
      
      if (!orgHeader || orgHeader.trim() === '' || orgHeader.trim() === 'undefined') {
        // BACKWARD COMPATIBLE: No header provided → default to current orgId from token
        req.orgIds    = [req.user.orgId];
        req.orgFilter = { orgId: req.user.orgId };
      } else if (orgHeader.trim() === 'ALL') {
        // User selected all organizations — use all orgs they belong to
        req.orgIds    = userOrgIds;
        req.orgFilter = userOrgIds.length === 1 
          ? { orgId: userOrgIds[0] }
          : { orgId: { $in: userOrgIds } };
      } else {
        // User selected specific org(s) — validate they have access
        const requestedOrgIds = orgHeader.split(',').map(s => s.trim()).filter(Boolean);
        if (requestedOrgIds.length === 0) {
          return res.status(400).json({
            success: false,
            error: 'Invalid organization context',
            message: 'x-org-ids header contains no valid organization IDs.',
            code: 'INVALID_ORG_CONTEXT',
          });
        }
        
        // Filter to only orgs user has access to
        const permittedOrgIds = requestedOrgIds.filter(id => userOrgIds.includes(id));
        if (permittedOrgIds.length === 0) {
          return res.status(403).json({
            success: false,
            error: 'Organization access denied',
            message: 'You do not have access to the requested organization(s).',
            code: 'ORG_ACCESS_DENIED',
          });
        }
        
        req.orgIds    = permittedOrgIds;
        req.orgFilter = permittedOrgIds.length === 1
          ? { orgId: permittedOrgIds[0] }
          : { orgId: { $in: permittedOrgIds } };
      }
      
      // Store user's organizations for downstream use
      req.user.organizations = user.organizations || [];

      // ─── Branch access control ──────────────────────────────────────────────
      // owners and admins always have full access to all branches.
      // For other roles, check allowedBranches on the user's org entry.
      // If allowedBranches is absent or empty → backward-compatible: allow all.
      // NOTE: When multiple orgs selected, branch restrictions apply per-org
      const role = req.user.role;
      if (role !== 'owner' && role !== 'admin') {
        // Collect allowed branches across all selected organizations
        let allAllowedBranches = [];
        let hasAnyRestriction = false;
        
        for (const selectedOrgId of req.orgIds) {
          const orgEntry = (user.organizations || []).find(o => o.orgId === selectedOrgId);
          const allowedBranches = orgEntry?.allowedBranches || [];
          
          if (allowedBranches.length > 0) {
            hasAnyRestriction = true;
            allAllowedBranches.push(...allowedBranches);
          }
        }
        
        // Remove duplicates
        allAllowedBranches = [...new Set(allAllowedBranches)];

        // Only enforce if at least one org has branch restrictions
        if (hasAnyRestriction && allAllowedBranches.length > 0) {
          if (req.branchIds.length === 0) {
            // User requested ALL branches — restrict to their allowed set
            req.branchIds    = allAllowedBranches;
            req.branchFilter = { branchId: { $in: allAllowedBranches } };
          } else {
            // User requested specific branches — keep only the ones they're allowed
            const permitted = req.branchIds.filter(id => allAllowedBranches.includes(id));
            if (permitted.length === 0) {
              return res.status(403).json({
                success: false,
                error:   'Branch access denied',
                message: 'You do not have access to the requested branch(es).',
                code:    'BRANCH_ACCESS_DENIED',
              });
            }
            req.branchIds    = permitted;
            req.branchFilter = { branchId: { $in: permitted } };
          }
        }
      }
      
      // expose allowedBranches for current org (for backward compatibility with single-org mode)
      const currentOrgEntry = (user.organizations || []).find(o => o.orgId === req.user.orgId);
      req.user.allowedBranches = currentOrgEntry?.allowedBranches || [];
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

// ─── Helper: build branch-aware query filter ──────────────────────────────────
const applyBranchFilter = (baseQuery, branchFilter) => {
  if (!branchFilter || Object.keys(branchFilter).length === 0) return baseQuery;
  return { ...baseQuery, ...branchFilter };
};

module.exports = { generateFinanceToken, verifyFinanceJWT, requireOwnerOrAdmin, applyBranchFilter, FINANCE_SECRET };
