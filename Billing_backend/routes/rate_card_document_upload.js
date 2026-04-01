// ============================================================================
// ABRA FLEET — RATE CARD DOCUMENT UPLOAD
// ============================================================================
// File: backend/routes/rate_card_document_upload.js
//
// ADD TO rate_cards.js at the bottom (before module.exports):
//
//   const docUploadRouter = require('./rate_card_document_upload');
//   router.use('/', docUploadRouter);
//
// OR add these routes directly into rate_cards.js
// ============================================================================

const express = require('express');
const router  = express.Router();
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');
const mongoose = require('mongoose');

// Reuse RateCard model from rate_cards.js
// If standalone, re-import it:
// const { RateCard } = require('./rate_cards');

// ── Storage config ────────────────────────────────────────────────────────
const docStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'rate-card-documents');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `rc-doc-${Date.now()}-${safe}`);
  },
});

const docUpload = multer({
  storage: docStorage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20 MB
  fileFilter: (req, file, cb) => {
    const allowed = /pdf|jpg|jpeg|png|doc|docx/;
    const ext     = allowed.test(path.extname(file.originalname).toLowerCase());
    const mime    = allowed.test(file.mimetype);
    if (ext || mime) cb(null, true);
    else cb(new Error('Only PDF, JPG, PNG, DOC files allowed'));
  },
});

// ── POST /api/rate-cards/:id/upload-document ──────────────────────────────
router.post('/:id/upload-document', docUpload.single('document'), async (req, res) => {
  try {
    const { RateCard } = require('./rate_cards');
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });

    // Add to documents array on the rate card
    if (!card.documents) card.documents = [];
    card.documents.push({
      filename:    req.file.originalname,
      storedName:  req.file.filename,
      filepath:    `/uploads/rate-card-documents/${req.file.filename}`,
      mimetype:    req.file.mimetype,
      size:        req.file.size,
      uploadedBy:  req.user?.email || 'admin',
      uploadedAt:  new Date(),
    });

    card.updatedBy = req.user?.email || 'admin';
    await card.save();

    console.log(`✅ Document uploaded for rate card ${card.rateCardId}: ${req.file.originalname}`);

    res.json({
      success: true,
      message: `${req.file.originalname} uploaded successfully`,
      data: {
        filename:  req.file.originalname,
        filepath:  `/uploads/rate-card-documents/${req.file.filename}`,
        size:      req.file.size,
        uploadedAt: new Date(),
      },
    });
  } catch (err) {
    console.error('Document upload error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── DELETE /api/rate-cards/:id/documents/:filename ────────────────────────
router.delete('/:id/documents/:filename', async (req, res) => {
  try {
    const { RateCard } = require('./rate_cards');
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    const docIndex = (card.documents || []).findIndex(
      d => d.storedName === req.params.filename || d.filename === req.params.filename
    );

    if (docIndex === -1) {
      return res.status(404).json({ success: false, error: 'Document not found' });
    }

    const doc = card.documents[docIndex];

    // Delete file from disk
    const fullPath = path.join(__dirname, '..', 'uploads', 'rate-card-documents', doc.storedName);
    if (fs.existsSync(fullPath)) fs.unlinkSync(fullPath);

    card.documents.splice(docIndex, 1);
    card.updatedBy = req.user?.email || 'admin';
    await card.save();

    res.json({ success: true, message: 'Document deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;

// ============================================================================
// ALSO ADD THIS TO YOUR RateCard SCHEMA in rate_cards.js
// (inside the rateCardSchema definition, before the timestamps: true line)
// ============================================================================
/*
  documents: [{
    filename:   String,
    storedName: String,
    filepath:   String,
    mimetype:   String,
    size:       Number,
    uploadedBy: String,
    uploadedAt: { type: Date, default: Date.now },
  }],
*/

// ============================================================================
// HOW TO NAVIGATE TO RATE CARD DETAIL SCREEN FROM FLUTTER:
// ============================================================================
/*
  // From your rate cards list screen:
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => RateCardDetailScreen(
      rateCardId: card['_id'],
      authToken: yourAuthToken,
    ),
  ));
*/

// ============================================================================
// PUBSPEC DEPENDENCIES NEEDED FOR DETAIL SCREEN:
// ============================================================================
/*
  dependencies:
    http: ^1.2.0
    intl: ^0.19.0
    file_picker: ^8.0.0
    url_launcher: ^6.3.0
*/