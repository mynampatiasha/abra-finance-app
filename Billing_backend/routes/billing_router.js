const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// ==================== CONTRACTS ====================

// Get all contracts
router.get('/contracts', async (req, res) => {
  try {
    const contracts = await req.db.collection('contracts').find({}).toArray();
    res.json({ success: true, contracts });
  } catch (error) {
    console.error('Error fetching contracts:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get contract by ID
router.get('/contracts/:contractId', async (req, res) => {
  try {
    const contract = await req.db.collection('contracts').findOne({ 
      contractId: req.params.contractId 
    });
    
    if (!contract) {
      return res.status(404).json({ success: false, error: 'Contract not found' });
    }
    
    res.json({ success: true, contract });
  } catch (error) {
    console.error('Error fetching contract:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get active contracts for organization
router.get('/contracts/organization/:organizationId', async (req, res) => {
  try {
    const now = new Date();
    const contracts = await req.db.collection('contracts').find({
      organizationId: req.params.organizationId,
      status: 'active',
      endDate: { $gte: now }
    }).toArray();
    
    res.json({ success: true, contracts });
  } catch (error) {
    console.error('Error fetching organization contracts:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Create new contract
router.post('/contracts', async (req, res) => {
  try {
    const contract = {
      ...req.body,
      createdAt: new Date(),
      lastModifiedAt: new Date()
    };

    
    const result = await req.db.collection('contracts').insertOne(contract);
    
    // Log audit entry
    await req.db.collection('audit_logs').insertOne({
      entityType: 'contract',
      entityId: contract.contractId,
      action: 'created',
      userId: req.user?.uid || 'system',
      userName: req.user?.name || 'System',
      timestamp: new Date(),
      changes: contract
    });
    
    res.json({ success: true, contractId: result.insertedId, contract });
  } catch (error) {
    console.error('Error creating contract:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Update contract
router.put('/contracts/:contractId', async (req, res) => {
  try {
    const oldContract = await req.db.collection('contracts').findOne({ 
      contractId: req.params.contractId 
    });
    
    if (!oldContract) {
      return res.status(404).json({ success: false, error: 'Contract not found' });
    }
    
    const updatedContract = {
      ...req.body,
      lastModifiedAt: new Date(),
      modifiedBy: req.user?.name || 'System'
    };
    
    await req.db.collection('contracts').updateOne(
      { contractId: req.params.contractId },
      { $set: updatedContract }
    );
    
    // Log audit entry
    await req.db.collection('audit_logs').insertOne({
      entityType: 'contract',
      entityId: req.params.contractId,
      action: 'modified',
      userId: req.user?.uid || 'system',
      userName: req.user?.name || 'System',
      timestamp: new Date(),
      changes: { old: oldContract, new: updatedContract }
    });
    
    res.json({ success: true, message: 'Contract updated successfully' });
  } catch (error) {
    console.error('Error updating contract:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ==================== INVOICES ====================

// Get all invoices
router.get('/invoices', async (req, res) => {
  try {
    const { organizationId, status, startDate, endDate } = req.query;
    
    let query = {};
    if (organizationId) query.organizationId = organizationId;
    if (status) query.status = status;
    if (startDate && endDate) {
      query.date = {
        $gte: new Date(startDate),
        $lte: new Date(endDate)
      };
    }
    
    const invoices = await req.db.collection('invoices')
      .find(query)
      .sort({ date: -1 })
      .toArray();
    
    res.json({ success: true, invoices });
  } catch (error) {
    console.error('Error fetching invoices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get invoice by ID
router.get('/invoices/:invoiceId', async (req, res) => {
  try {
    const invoice = await req.db.collection('invoices').findOne({ 
      id: req.params.invoiceId 
    });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    res.json({ success: true, invoice });
  } catch (error) {
    console.error('Error fetching invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Generate invoice from contract
router.post('/invoices/generate', async (req, res) => {
  try {
    const { contractId, tripIds, billingPeriodStart, billingPeriodEnd } = req.body;
    
    // Get contract
    const contract = await req.db.collection('contracts').findOne({ contractId });
    if (!contract) {
      return res.status(404).json({ success: false, error: 'Contract not found' });
    }
    
    // Validate contract is active
    if (contract.status !== 'active') {
      return res.status(400).json({ success: false, error: 'Contract is not active' });
    }
    
    // Get trips
    const trips = await req.db.collection('trips').find({
      _id: { $in: tripIds.map(id => new ObjectId(id)) }
    }).toArray();
    
    // Calculate invoice using contract pricing
    const invoice = calculateInvoiceFromContract(contract, trips, billingPeriodStart, billingPeriodEnd);
    
    // Save invoice
    const result = await req.db.collection('invoices').insertOne(invoice);
    
    // Log audit entry
    await req.db.collection('audit_logs').insertOne({
      entityType: 'invoice',
      entityId: invoice.id,
      action: 'created',
      userId: req.user?.uid || 'system',
      userName: req.user?.name || 'System',
      timestamp: new Date(),
      changes: invoice
    });
    
    res.json({ success: true, invoice });
  } catch (error) {
    console.error('Error generating invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Update invoice payment
router.patch('/invoices/:invoiceId/payment', async (req, res) => {
  try {
    const { amountPaid, paymentMode, paidDate } = req.body;
    
    const invoice = await req.db.collection('invoices').findOne({ id: req.params.invoiceId });
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    const totalPaid = (invoice.amountPaid || 0) + amountPaid;
    let status = 'Pending';
    if (totalPaid >= invoice.totalAmount) {
      status = 'Paid';
    } else if (totalPaid > 0) {
      status = 'Partially Paid';
    }
    
    await req.db.collection('invoices').updateOne(
      { id: req.params.invoiceId },
      { 
        $set: { 
          amountPaid: totalPaid,
          status,
          paymentMode,
          paidDate: paidDate || new Date(),
          lastModifiedAt: new Date()
        }
      }
    );
    
    // Log audit entry
    await req.db.collection('audit_logs').insertOne({
      entityType: 'invoice',
      entityId: req.params.invoiceId,
      action: 'payment_recorded',
      userId: req.user?.uid || 'system',
      userName: req.user?.name || 'System',
      timestamp: new Date(),
      changes: { amountPaid, paymentMode, paidDate }
    });
    
    res.json({ success: true, message: 'Payment recorded successfully' });
  } catch (error) {
    console.error('Error recording payment:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ==================== HELPER FUNCTIONS ====================

function calculateInvoiceFromContract(contract, trips, billingPeriodStart, billingPeriodEnd) {
  let totalAmount = 0;
  const chargeBreakdown = [];
  const vehicleTypeCosts = {};
  
  // Calculate charges for each trip
  trips.forEach(trip => {
    const vehicleType = trip.vehicleType || 'Unknown';
    const distance = trip.distance || 0;
    const waitingMinutes = trip.waitingMinutes || 0;
    const tripDateTime = new Date(trip.startTime);
    
    const pricing = contract.vehiclePricing[vehicleType];
    if (!pricing) {
      throw new Error(`No pricing found for vehicle type: ${vehicleType}`);
    }
    
    let tripCost = 0;
    
    // Base fare
    tripCost += pricing.baseFarePerTrip;
    
    // Distance charge
    tripCost += distance * pricing.ratePerKm;
    
    // Waiting charge (after grace period)
    if (waitingMinutes > pricing.gracePeriodMinutes) {
      tripCost += (waitingMinutes - pricing.gracePeriodMinutes) * pricing.ratePerMinuteWaiting;
    }
    
    // Apply surcharges
    if (isPeakHour(tripDateTime)) {
      tripCost += tripCost * (contract.surcharges.peakHoursPercent / 100);
    }
    if (isNightShift(tripDateTime)) {
      tripCost += tripCost * (contract.surcharges.nightShiftPercent / 100);
    }
    if (isWeekend(tripDateTime)) {
      tripCost += tripCost * (contract.surcharges.weekendPercent / 100);
    }
    
    // Ensure minimum charge
    if (tripCost < pricing.minimumChargePerTrip) {
      tripCost = pricing.minimumChargePerTrip;
    }
    
    vehicleTypeCosts[vehicleType] = (vehicleTypeCosts[vehicleType] || 0) + tripCost;
    totalAmount += tripCost;
  });
  
  // Apply volume discount
  const totalTrips = trips.length;
  const applicableSlab = getApplicableVolumeSlab(contract, totalTrips);
  let discountAmount = 0;
  if (applicableSlab && applicableSlab.discountPercent > 0) {
    discountAmount = totalAmount * (applicableSlab.discountPercent / 100);
    totalAmount -= discountAmount;
    chargeBreakdown.push({
      type: 'Volume Discount',
      description: `${applicableSlab.discountPercent}% off for ${totalTrips} trips`,
      amount: -discountAmount
    });
  }
  
  // Apply minimum commitment
  let minimumApplied = false;
  if (totalAmount < contract.paymentTerms.monthlyMinimum) {
    const minimumCharge = contract.paymentTerms.monthlyMinimum - totalAmount;
    chargeBreakdown.push({
      type: 'Minimum Commitment',
      description: 'Monthly minimum billing guarantee',
      amount: minimumCharge
    });
    totalAmount = contract.paymentTerms.monthlyMinimum;
    minimumApplied = true;
  }
  
  // Check maximum limit
  if (totalAmount > contract.paymentTerms.monthlyMaximum) {
    throw new Error(`Invoice amount exceeds monthly maximum: ${contract.paymentTerms.monthlyMaximum}`);
  }
  
  // Calculate GST (18%)
  const gstAmount = totalAmount * 0.18;
  const totalWithGst = totalAmount + gstAmount;
  
  // Calculate due date
  const dueDate = new Date(billingPeriodEnd);
  dueDate.setDate(dueDate.getDate() + contract.paymentTerms.paymentDueDays);
  
  // Generate invoice
  return {
    id: generateInvoiceNumber(),
    contractId: contract.contractId,
    organizationId: contract.organizationId,
    organizationName: contract.organizationName,
    agreementId: contract.contractId,
    agreementStartDate: contract.startDate,
    agreementEndDate: contract.endDate,
    billingCycle: contract.paymentTerms.billingCycle,
    paymentTerms: `Net ${contract.paymentTerms.paymentDueDays}`,
    billingPeriodStart,
    billingPeriodEnd,
    amount: totalAmount,
    gstAmount,
    totalAmount: totalWithGst,
    amountPaid: 0,
    status: 'Pending',
    date: billingPeriodEnd,
    dueDate,
    paidDate: null,
    paymentMode: null,
    trips: totalTrips,
    chargeBreakdown,
    pricingReference: {
      contractId: contract.contractId,
      volumeSlabApplied: applicableSlab,
      minimumCommitmentApplied: minimumApplied,
      discountAmount
    },
    vehicleTypeCosts,
    createdAt: new Date()
  };
}

function isPeakHour(dateTime) {
  const hour = dateTime.getHours();
  return (hour >= 8 && hour < 10) || (hour >= 17 && hour < 20);
}

function isNightShift(dateTime) {
  const hour = dateTime.getHours();
  return hour >= 22 || hour < 6;
}

function isWeekend(dateTime) {
  const day = dateTime.getDay();
  return day === 0 || day === 6; // Sunday or Saturday
}

function getApplicableVolumeSlab(contract, tripCount) {
  for (const slab of contract.volumeSlabs) {
    if (tripCount >= slab.minTrips && tripCount <= slab.maxTrips) {
      return slab;
    }
  }
  return null;
}

function generateInvoiceNumber() {
  // Legacy contract billing — uses unique timestamp-based ID in separate collection
  return `INV${Date.now()}`;
}

module.exports = router;
