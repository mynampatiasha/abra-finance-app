// ============================================================================
// RECONCILIATION MODEL
// ============================================================================
// File: backend/models/Reconciliation.js
// ============================================================================

'use strict';

const mongoose = require('mongoose');

const ReconciliationSchema = new mongoose.Schema({
  accountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'PaymentAccount',
    required: true,
    index: true,
  },
  orgId: {
    type: String,
    default: null,
    index: true,
  },

  // ── Period ────────────────────────────────────────────────────────────────
  startDate: { type: Date, required: true },
  endDate:   { type: Date, required: true },

  // ── Balances ──────────────────────────────────────────────────────────────
  openingBalance: { type: Number, default: 0 },   // auto-calc from prev reconciliation
  closingBalance: { type: Number, required: true }, // entered by user from bank statement
  clearedAmount:  { type: Number, default: 0 },    // live sum of ticked transactions
  difference:     { type: Number, default: 0 },    // closingBalance - clearedAmount

  // ── Status ────────────────────────────────────────────────────────────────
  status: {
    type: String,
    enum: ['IN_PROGRESS', 'RECONCILED'],
    default: 'IN_PROGRESS',
  },

  // ── Transaction IDs user has ticked as cleared ────────────────────────────
  clearedTxnIds: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'ProviderTransaction',
  }],

  // ── Transaction IDs added via +Add Transaction inside reconciliation ───────
  addedTxnIds: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'ProviderTransaction',
  }],

  // ── Optional attachment (bank statement PDF etc.) ─────────────────────────
  attachmentUrl:  { type: String, default: null },
  attachmentName: { type: String, default: null },
  notes:          { type: String, default: null },

  // ── Timestamps ────────────────────────────────────────────────────────────
  reconciledAt: { type: Date, default: null },
  createdAt:    { type: Date, default: Date.now },
  updatedAt:    { type: Date, default: Date.now },
  createdBy:    { type: String, default: 'system' },
});

ReconciliationSchema.pre('save', async function () {
  this.updatedAt  = new Date();
  this.difference = (this.closingBalance || 0) - (this.clearedAmount || 0);
});

const Reconciliation = mongoose.models.Reconciliation
  || mongoose.model('Reconciliation', ReconciliationSchema, 'reconciliations');

module.exports = Reconciliation;