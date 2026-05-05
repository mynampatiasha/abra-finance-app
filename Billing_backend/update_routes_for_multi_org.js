#!/usr/bin/env node
/**
 * Script to update route files for multi-organization support
 * 
 * Changes:
 * - orgId: req.user?.orgId  →  ...req.orgFilter
 * - orgId: req.user.orgId   →  ...req.orgFilter
 * - { orgId: req.user?.orgId, ...req.branchFilter }  →  { ...req.orgFilter, ...req.branchFilter }
 * 
 * Usage: node update_routes_for_multi_org.js
 */

const fs = require('fs');
const path = require('path');

const ROUTES_DIR = path.join(__dirname, 'routes');
const BACKUP_SUFFIX = '.before_multi_org';

// Files to skip (backup files, etc.)
const SKIP_FILES = [
  '.before_branch',
  '.before_multi_org',
  '.backup',
  '.antigravity',
  "''",
];

function shouldSkipFile(filename) {
  return SKIP_FILES.some(suffix => filename.includes(suffix));
}

function updateFileContent(content, filename) {
  let updated = content;
  let changeCount = 0;

  // Pattern 1: { orgId: req.user?.orgId, ...req.branchFilter }  →  { ...req.orgFilter, ...req.branchFilter }
  const pattern1 = /\{\s*orgId:\s*req\.user\?\.orgId\s*,\s*\.\.\.(req\.branchFilter[^}]*)\}/g;
  const matches1 = content.match(pattern1);
  if (matches1) {
    updated = updated.replace(pattern1, '{ ...req.orgFilter, ...$1}');
    changeCount += matches1.length;
    console.log(`  ✓ Pattern 1: ${matches1.length} occurrence(s)`);
  }

  // Pattern 2: { orgId: req.user.orgId, ...req.branchFilter }  →  { ...req.orgFilter, ...req.branchFilter }
  const pattern2 = /\{\s*orgId:\s*req\.user\.orgId\s*,\s*\.\.\.(req\.branchFilter[^}]*)\}/g;
  const matches2 = content.match(pattern2);
  if (matches2) {
    updated = updated.replace(pattern2, '{ ...req.orgFilter, ...$1}');
    changeCount += matches2.length;
    console.log(`  ✓ Pattern 2: ${matches2.length} occurrence(s)`);
  }

  // Pattern 3: orgId: req.user?.orgId (standalone, not in object with branchFilter)
  // Only replace if NOT followed by comma and branchFilter
  const pattern3 = /orgId:\s*req\.user\?\.orgId(?!\s*,\s*\.\.\.)/g;
  const matches3 = content.match(pattern3);
  if (matches3) {
    // This is trickier - need to replace with ...req.orgFilter but maintain object structure
    // For now, just log these for manual review
    console.log(`  ⚠️  Pattern 3: ${matches3.length} occurrence(s) - NEEDS MANUAL REVIEW`);
  }

  // Pattern 4: ...(req.user?.orgId ? { orgId: req.user.orgId } : {})  →  ...req.orgFilter
  const pattern4 = /\.\.\.\(req\.user\?\.orgId\s*\?\s*\{\s*orgId:\s*req\.user\.orgId\s*\}\s*:\s*\{\}\)/g;
  const matches4 = content.match(pattern4);
  if (matches4) {
    updated = updated.replace(pattern4, '...req.orgFilter');
    changeCount += matches4.length;
    console.log(`  ✓ Pattern 4: ${matches4.length} occurrence(s)`);
  }

  return { updated, changeCount };
}

function processFile(filepath) {
  const filename = path.basename(filepath);
  
  if (shouldSkipFile(filename)) {
    return { skipped: true };
  }

  if (!filename.endsWith('.js')) {
    return { skipped: true };
  }

  try {
    const content = fs.readFileSync(filepath, 'utf8');
    const { updated, changeCount } = updateFileContent(content, filename);

    if (changeCount > 0) {
      // Create backup
      const backupPath = filepath + BACKUP_SUFFIX;
      if (!fs.existsSync(backupPath)) {
        fs.writeFileSync(backupPath, content, 'utf8');
      }

      // Write updated content
      fs.writeFileSync(filepath, updated, 'utf8');
      
      return { updated: true, changeCount };
    }

    return { unchanged: true };
  } catch (error) {
    return { error: error.message };
  }
}

function main() {
  console.log('🔄 Updating route files for multi-organization support...\n');

  const files = fs.readdirSync(ROUTES_DIR);
  let totalUpdated = 0;
  let totalSkipped = 0;
  let totalUnchanged = 0;
  let totalErrors = 0;
  let totalChanges = 0;

  files.forEach(file => {
    const filepath = path.join(ROUTES_DIR, file);
    const stats = fs.statSync(filepath);

    if (!stats.isFile()) return;

    const result = processFile(filepath);

    if (result.skipped) {
      totalSkipped++;
    } else if (result.updated) {
      console.log(`✅ ${file} - ${result.changeCount} change(s)`);
      totalUpdated++;
      totalChanges += result.changeCount;
    } else if (result.unchanged) {
      totalUnchanged++;
    } else if (result.error) {
      console.log(`❌ ${file} - ERROR: ${result.error}`);
      totalErrors++;
    }
  });

  console.log('\n📊 Summary:');
  console.log(`  Updated: ${totalUpdated} file(s) (${totalChanges} total changes)`);
  console.log(`  Unchanged: ${totalUnchanged} file(s)`);
  console.log(`  Skipped: ${totalSkipped} file(s)`);
  console.log(`  Errors: ${totalErrors} file(s)`);
  console.log('\n✅ Done! Backups saved with .before_multi_org suffix');
  console.log('\n⚠️  IMPORTANT: Review files with "NEEDS MANUAL REVIEW" warnings');
}

main();
