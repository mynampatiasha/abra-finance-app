// ============================================================================
// FILE UPLOAD MIDDLEWARE - MULTER CONFIGURATION
// ============================================================================
// Handles file uploads for payment proofs, documents, etc.
// ============================================================================

const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Ensure uploads directory exists
const uploadsDir = path.join(__dirname, '../uploads');
const paymentProofsDir = path.join(uploadsDir, 'payment-proofs');
const documentsDir = path.join(uploadsDir, 'documents');

// Create directories if they don't exist
[uploadsDir, paymentProofsDir, documentsDir].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    console.log(`📁 Created directory: ${dir}`);
  }
});

// ============================================================================
// STORAGE CONFIGURATION
// ============================================================================

// Storage for payment proofs
const paymentProofStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, paymentProofsDir);
  },
  filename: function (req, file, cb) {
    // Generate unique filename: timestamp-randomstring-originalname
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    const nameWithoutExt = path.basename(file.originalname, ext);
    cb(null, `${nameWithoutExt}-${uniqueSuffix}${ext}`);
  }
});

// Storage for general documents
const documentStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, documentsDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    const nameWithoutExt = path.basename(file.originalname, ext);
    cb(null, `${nameWithoutExt}-${uniqueSuffix}${ext}`);
  }
});

// ============================================================================
// FILE FILTER
// ============================================================================

// File filter for payment proofs (images and PDFs)
const paymentProofFileFilter = (req, file, cb) => {
  const allowedTypes = /jpeg|jpg|png|gif|pdf/;
  const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
  const mimetype = allowedTypes.test(file.mimetype);

  if (mimetype && extname) {
    return cb(null, true);
  } else {
    cb(new Error('Only images (JPEG, JPG, PNG, GIF) and PDF files are allowed for payment proofs'));
  }
};

// File filter for general documents
const documentFileFilter = (req, file, cb) => {
  const allowedTypes = /jpeg|jpg|png|gif|pdf|doc|docx|xls|xlsx/;
  const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
  const mimetype = allowedTypes.test(file.mimetype);

  if (mimetype && extname) {
    return cb(null, true);
  } else {
    cb(new Error('Invalid file type. Allowed: images, PDF, DOC, DOCX, XLS, XLSX'));
  }
};

// ============================================================================
// MULTER INSTANCES
// ============================================================================

// Upload middleware for payment proofs (multiple files)
const uploadPaymentProofs = multer({
  storage: paymentProofStorage,
  fileFilter: paymentProofFileFilter,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB per file
  }
}).array('paymentProofs', 10); // Max 10 files

// Upload middleware for single document
const uploadSingleDocument = multer({
  storage: documentStorage,
  fileFilter: documentFileFilter,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB
  }
}).single('document');

// Upload middleware for multiple documents
const uploadMultipleDocuments = multer({
  storage: documentStorage,
  fileFilter: documentFileFilter,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB per file
  }
}).array('documents', 20); // Max 20 files

// ============================================================================
// ERROR HANDLING WRAPPER
// ============================================================================

// Wrapper to handle multer errors gracefully
const handleUploadError = (uploadMiddleware) => {
  return (req, res, next) => {
    uploadMiddleware(req, res, (err) => {
      if (err instanceof multer.MulterError) {
        // Multer-specific errors
        if (err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            success: false,
            message: 'File size too large. Maximum size is 10MB per file.',
            error: err.message
          });
        } else if (err.code === 'LIMIT_FILE_COUNT') {
          return res.status(400).json({
            success: false,
            message: 'Too many files. Maximum allowed files exceeded.',
            error: err.message
          });
        } else if (err.code === 'LIMIT_UNEXPECTED_FILE') {
          return res.status(400).json({
            success: false,
            message: 'Unexpected field name in file upload.',
            error: err.message
          });
        } else {
          return res.status(400).json({
            success: false,
            message: 'File upload error',
            error: err.message
          });
        }
      } else if (err) {
        // Other errors (e.g., file filter errors)
        return res.status(400).json({
          success: false,
          message: err.message || 'File upload failed',
          error: err.message
        });
      }
      
      // No error, proceed
      next();
    });
  };
};

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Raw multer instances (use with caution)
  uploadPaymentProofs,
  uploadSingleDocument,
  uploadMultipleDocuments,
  
  // Wrapped versions with error handling (recommended)
  uploadPaymentProofsWithErrorHandling: handleUploadError(uploadPaymentProofs),
  uploadSingleDocumentWithErrorHandling: handleUploadError(uploadSingleDocument),
  uploadMultipleDocumentsWithErrorHandling: handleUploadError(uploadMultipleDocuments),
  
  // Utility functions
  getPaymentProofsDir: () => paymentProofsDir,
  getDocumentsDir: () => documentsDir,
  getUploadsDir: () => uploadsDir,
};
