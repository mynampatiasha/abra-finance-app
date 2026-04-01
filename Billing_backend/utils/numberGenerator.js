// ============================================================================
// SHARED NUMBER GENERATOR UTILITY
// ============================================================================
// Format: PREFIX + 6-digit zero-padded sequence, scoped per orgId
// Example: INV000001, INV000002 ... per org independently
// ============================================================================

/**
 * Generate the next sequential document number for a given org.
 *
 * @param {mongoose.Model} Model      - Mongoose model to query
 * @param {string}         field      - Field name that holds the number (e.g. 'invoiceNumber')
 * @param {string}         prefix     - Prefix string (e.g. 'INV', 'CN', 'BILL')
 * @param {string|null}    orgId      - Organisation ID (null = no org scope)
 * @returns {Promise<string>}         - e.g. 'INV000001'
 */
async function generateNumber(Model, field, prefix, orgId = null) {
  const query = { [field]: new RegExp(`^${prefix}\\d`) };
  if (orgId) query.orgId = orgId;

  const existing = await Model.find(query).select(field).lean();

  let max = 0;
  for (const doc of existing) {
    const val = doc[field];
    if (!val) continue;
    // Extract trailing digits after the prefix
    const digits = val.slice(prefix.length);
    const n = parseInt(digits, 10);
    if (!isNaN(n) && n > max) max = n;
  }

  return `${prefix}${String(max + 1).padStart(6, '0')}`;
}

module.exports = { generateNumber };
