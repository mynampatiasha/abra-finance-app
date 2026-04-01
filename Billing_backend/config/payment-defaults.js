// ============================================================================
// DEFAULT PAYMENT DETAILS CONFIGURATION
// ============================================================================
// File: backend/config/payment-defaults.js
// Contains default bank/UPI details for invoices
// Edit these values to update company payment information
// ============================================================================

module.exports = {
  // Bank Account Details
  bankAccount: {
    accountHolder: 'Abra Fleet Management',
    accountNumber: '50200012345678',
    ifscCode: 'HDFC0001234',
    bankName: 'HDFC Bank',
    branchName: 'MG Road Branch' // Optional
  },
  
  // UPI Payment Details
  upi: {
    upiId: 'abrafleet@paytm',
    qrCode: '' // Optional: URL to QR code image
  },
  
  // Office Address (for Cash/Cheque payments)
  office: {
    address: '123 Main Street, MG Road',
    city: 'Bangalore',
    state: 'Karnataka',
    pincode: '560001',
    country: 'India',
    fullAddress: '123 Main Street, MG Road, Bangalore, Karnataka - 560001, India'
  },
  
  // Additional Payment Info
  additional: {
    gstNumber: '29ABRAFL1234A1Z5',
    panNumber: 'ABRAFL1234A', // Optional
    contactEmail: 'billing@abrafleet.com',
    contactPhone: '+91-9876543210',
    website: 'www.abrafleet.com' // Optional
  },
  
  // Payment Instructions
  instructions: {
    bankTransfer: 'Please use invoice number as reference while making payment',
    upi: 'Scan QR code or enter UPI ID to pay instantly',
    cheque: 'Cheques should be drawn in favor of "Abra Fleet Management"',
    general: 'Please share payment proof via email or WhatsApp after payment'
  }
};

// ============================================================================
// HOW TO UPDATE:
// ============================================================================
// 1. Edit the values above with your actual bank details
// 2. Save the file
// 3. Restart your backend server
// 4. All new invoices will use these updated details in emails
// ============================================================================