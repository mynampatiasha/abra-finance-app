// vendors.routes.js
// Simple Backend API routes for Vendor Management
// Place this file in your backend routes folder

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

/**
 * @route   GET /api/admin/vendors
 * @desc    Get all vendors with optional search
 * @access  Private
 */
router.get('/', async (req, res) => {
  try {
    const db = req.db; // Use req.db from middleware
    const { search } = req.query;
    
    // Build query
    let query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (search) {
      query = {
        ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        $or: [
          { name: { $regex: search, $options: 'i' } },
          { email: { $regex: search, $options: 'i' } },
          { phone: { $regex: search, $options: 'i' } },
          { location: { $regex: search, $options: 'i' } },
          { vehicles: { $regex: search, $options: 'i' } },
        ],
      };
    }
    
    const vendors = await db.collection('vendors')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();
    
    res.json({
      success: true,
      data: vendors,
    });
  } catch (error) {
    console.error('Error fetching vendors:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching vendors',
      error: error.message,
    });
  }
});

/**
 * @route   POST /api/admin/vendors
 * @desc    Create a new vendor
 * @access  Private
 */
router.post('/', async (req, res) => {
  try {
    const db = req.db; // Use req.db from middleware
    const { name, email, phone, location, vehicles } = req.body;
    
    // Validation
    if (!name || !email || !phone || !location) {
      return res.status(400).json({
        success: false,
        message: 'Name, email, phone, and location are required',
      });
    }
    
    // Check if vendor with same email already exists
    const existingVendor = await db.collection('vendors').findOne({ email });
    if (existingVendor) {
      return res.status(400).json({
        success: false,
        message: 'Vendor with this email already exists',
      });
    }
    
    // Create vendor object
    const vendor = {
      name,
      email,
      phone,
      location,
      vehicles: vehicles || [],
      orgId: req.user?.orgId || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      createdBy: req.user.userId,
    };
    
    const result = await db.collection('vendors').insertOne(vendor);
    
    res.status(201).json({
      success: true,
      message: 'Vendor created successfully',
      data: {
        _id: result.insertedId,
        ...vendor,
      },
    });
  } catch (error) {
    console.error('Error creating vendor:', error);
    res.status(500).json({
      success: false,
      message: 'Error creating vendor',
      error: error.message,
    });
  }
});

/**
 * @route   PUT /api/admin/vendors/:id
 * @desc    Update a vendor
 * @access  Private
 */
router.put('/:id', async (req, res) => {
  try {
    const db = req.db; // Use req.db from middleware
    const { id } = req.params;
    const { name, email, phone, location, vehicles } = req.body;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid vendor ID',
      });
    }
    
    // Build update object
    const updateData = {
      updatedAt: new Date().toISOString(),
      updatedBy: req.user.userId,
    };
    
    if (name) updateData.name = name;
    if (email) updateData.email = email;
    if (phone) updateData.phone = phone;
    if (location) updateData.location = location;
    if (vehicles !== undefined) updateData.vehicles = vehicles;
    
    const result = await db.collection('vendors').findOneAndUpdate(
      { _id: new ObjectId(id) },
      { $set: updateData },
      { returnDocument: 'after' }
    );
    
    if (!result.value) {
      return res.status(404).json({
        success: false,
        message: 'Vendor not found',
      });
    }
    
    res.json({
      success: true,
      message: 'Vendor updated successfully',
      data: result.value,
    });
  } catch (error) {
    console.error('Error updating vendor:', error);
    res.status(500).json({
      success: false,
      message: 'Error updating vendor',
      error: error.message,
    });
  }
});

/**
 * @route   DELETE /api/admin/vendors/:id
 * @desc    Delete a vendor
 * @access  Private
 */
router.delete('/:id', async (req, res) => {
  try {
    const db = req.db; // Use req.db from middleware
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid vendor ID',
      });
    }
    
    const result = await db.collection('vendors').deleteOne({
      _id: new ObjectId(id),
    });
    
    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Vendor not found',
      });
    }
    
    res.json({
      success: true,
      message: 'Vendor deleted successfully',
    });
  } catch (error) {
    console.error('Error deleting vendor:', error);
    res.status(500).json({
      success: false,
      message: 'Error deleting vendor',
      error: error.message,
    });
  }
});

/**
 * @route   POST /api/admin/vendors/:id/vehicles
 * @desc    Add vehicle to vendor
 * @access  Private
 */
router.post('/:id/vehicles', async (req, res) => {
  try {
    const db = req.db; // Use req.db from middleware
    const { id } = req.params;
    const { vehicleNumber } = req.body;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid vendor ID',
      });
    }
    
    if (!vehicleNumber) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle number is required',
      });
    }
    
    // Check if vehicle already exists in this vendor
    const vendor = await db.collection('vendors').findOne({
      _id: new ObjectId(id),
    });
    
    if (!vendor) {
      return res.status(404).json({
        success: false,
        message: 'Vendor not found',
      });
    }
    
    if (vendor.vehicles && vendor.vehicles.includes(vehicleNumber)) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle already added to this vendor',
      });
    }
    
    // Add vehicle
    const result = await db.collection('vendors').findOneAndUpdate(
      { _id: new ObjectId(id) },
      { 
        $push: { vehicles: vehicleNumber },
        $set: { updatedAt: new Date().toISOString() }
      },
      { returnDocument: 'after' }
    );
    
    res.json({
      success: true,
      message: 'Vehicle added successfully',
      data: result.value,
    });
  } catch (error) {
    console.error('Error adding vehicle:', error);
    res.status(500).json({
      success: false,
      message: 'Error adding vehicle',
      error: error.message,
    });
  }
});

/**
 * @route   DELETE /api/admin/vendors/:id/vehicles/:vehicleNumber
 * @desc    Remove vehicle from vendor
 * @access  Private
 */
router.delete('/:id/vehicles/:vehicleNumber', async (req, res) => {
  try {
    const db = req.db; // Use req.db from middleware
    const { id, vehicleNumber } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid vendor ID',
      });
    }
    
    // Remove vehicle
    const result = await db.collection('vendors').findOneAndUpdate(
      { _id: new ObjectId(id) },
      { 
        $pull: { vehicles: vehicleNumber },
        $set: { updatedAt: new Date().toISOString() }
      },
      { returnDocument: 'after' }
    );
    
    if (!result.value) {
      return res.status(404).json({
        success: false,
        message: 'Vendor not found',
      });
    }
    
    res.json({
      success: true,
      message: 'Vehicle removed successfully',
      data: result.value,
    });
  } catch (error) {
    console.error('Error removing vehicle:', error);
    res.status(500).json({
      success: false,
      message: 'Error removing vehicle',
      error: error.message,
    });
  }
});

module.exports = router;