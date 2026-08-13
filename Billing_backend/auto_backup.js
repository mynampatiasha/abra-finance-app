const mongoose = require('mongoose');
const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

// Connect using the same URI from your live environment
const uri = process.env.MONGODB_URI;

if (!uri) {
  console.error("Error: MONGODB_URI not found.");
  process.exit(1);
}

async function runAutoBackup() {
  try {
    console.log("Connecting to MongoDB Atlas...");
    await mongoose.connect(uri);
    console.log("Connected successfully!");

    // Generate dynamic file name with Date and Time
    const now = new Date();
    // Format: YYYY-MM-DD_HH-MM-AM/PM
    const dateStr = now.toISOString().split('T')[0];
    const hours = now.getHours();
    const minutes = now.getMinutes().toString().padStart(2, '0');
    const ampm = hours >= 12 ? 'PM' : 'AM';
    const hour12 = hours % 12 || 12;
    
    // Example: Abra_Backup_2026-08-07_02-00-AM_TakenBy_SystemAuto
    const folderName = `Abra_Backup_${dateStr}_${hour12}-${minutes}-${ampm}_TakenBy_SystemAuto`;
    const backupDir = path.join(__dirname, 'backups', folderName);
    
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir, { recursive: true });
    }

    console.log("Saving backup to: " + backupDir);

    // Fetch all collections and save them as JSON files
    const collections = await mongoose.connection.db.listCollections().toArray();
    
    for (let col of collections) {
      const collectionName = col.name;
      const data = await mongoose.connection.db.collection(collectionName).find({}).toArray();
      
      const filePath = path.join(backupDir, collectionName + '.json');
      fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
    }

    console.log("✅ Backup successfully completed without affecting the live system!");

  } catch (error) {
    console.error("Backup failed!", error);
  } finally {
    // Close the database connection safely so the script exits
    mongoose.connection.close();
    process.exit(0);
  }
}

runAutoBackup();
