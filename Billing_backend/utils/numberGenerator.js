// ============================================================================
// SHARED NUMBER GENERATOR UTILITY
// ============================================================================
// Format: PREFIX + 6-digit zero-padded sequence, scoped per orgId + branchId
// Example: INV000001, INV000002 ... per org+branch independently
// ============================================================================

/**
 * Generate the next sequential document number for a given org + branch.
 *
 * @param {mongoose.Model} Model      - Mongoose model to query
 * @param {string}         field      - Field name that holds the number (e.g. 'invoiceNumber')
 * @param {string}         prefix     - Prefix string (e.g. 'INV', 'CN', 'BILL')
 * @param {string|null}    orgId      - Organisation ID (null = no org scope)
 * @param {string|null}    branchId   - Branch ID (null = no branch scope)
 * @returns {Promise<string>}         - e.g. 'INV000001'
 */
async function generateNumber(Model, field, prefix, orgId = null, branchId = null) {
  const query = { [field]: new RegExp(`^${prefix}\\d`) };
  if (orgId)    query.orgId    = orgId;
  if (branchId) query.branchId = branchId;

  const existing = await Model.find(query).select(field).lean();

  let max = 0;
  for (const doc of existing) {
    const val = doc[field];
    if (!val) continue;
    const digits = val.slice(prefix.length);
    const n = parseInt(digits, 10);
    if (!isNaN(n) && n > max) max = n;
  }

  // Gap-check: keep incrementing until we find a number not already in use
  let next = max + 1;
  let candidate = `${prefix}${String(next).padStart(6, '0')}`;

  const usedNumbers = new Set(existing.map(d => d[field]).filter(Boolean));
  while (usedNumbers.has(candidate)) {
    next++;
    candidate = `${prefix}${String(next).padStart(6, '0')}`;
  }

  return candidate;
}

module.exports = { generateNumber };
