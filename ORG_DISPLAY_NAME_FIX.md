# Organization Display Name Fix

## Issue
When "All Organizations" is selected in the organization switcher, the header still shows only one organization name (e.g., "Abra E-Logistics") instead of indicating that all organizations are being viewed.

## Expected Behavior
The organization display should show:
- **Single org selected**: Show the organization name (e.g., "Abra E-Logistics")
- **All organizations selected**: Show "All Organizations (3)" or "Entity Name (All 3 Orgs)" if entity name is set
- **Multiple specific orgs selected**: Show "3 Organizations" or "Entity Name (3 Orgs)" if entity name is set

## Solution Implemented

### 1. Added State Variable for Selected Organizations
Added `_selectedOrgIds` to track which organizations are currently selected:

```dart
// ── Organization selection data ───────────────────────────────────────────
List<String>                _selectedOrgIds     = [];  // ✅ NEW: Track selected org IDs
```

### 2. Created Computed Property `_orgLabel`
Similar to the existing `_branchLabel` getter, created `_orgLabel` to compute the display text:

```dart
String get _orgLabel {
  // Check if multi-org mode is active
  if (_organizations.length <= 1) {
    // Single org mode - show the org name
    return _orgName;
  }
  
  // Multi-org mode - check what's selected
  if (_selectedOrgIds.isEmpty) {
    // No selection or default to current org
    return _orgName;
  }
  
  if (_selectedOrgIds.length == 1 && _selectedOrgIds.first == 'ALL') {
    // All organizations selected
    if (_entityName != null && _entityName!.isNotEmpty) {
      return '$_entityName (All ${_organizations.length} Orgs)';
    }
    return 'All Organizations (${_organizations.length})';
  }
  
  if (_selectedOrgIds.length == 1) {
    // Single org selected - show its name
    final org = _organizations.firstWhere(
      (o) => o['orgId'] == _selectedOrgIds.first,
      orElse: () => {},
    );
    return (org['orgName'] as String?) ?? _orgName;
  }
  
  // Multiple specific orgs selected
  if (_entityName != null && _entityName!.isNotEmpty) {
    return '$_entityName (${_selectedOrgIds.length} Orgs)';
  }
  return '${_selectedOrgIds.length} Organizations';
}
```

### 3. Load Selected Organization IDs on Session Load
Updated `_loadSession()` to load the selected organization IDs from storage:

```dart
final selOrgs = await FinanceSecureStorage.getSelectedOrgIds();  // ✅ NEW: Load selected org IDs

// ... in setState:
_selectedOrgIds = selOrgs;  // ✅ NEW: Set selected org IDs
```

### 4. Updated Display to Use `_orgLabel`
Changed the organization chip in the header to use `_orgLabel` instead of `_orgName`:

```dart
// Header chip
Text(_orgLabel, style: const TextStyle(color: _kWhite, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)

// Sidebar display
Text(_orgLabel, style: const TextStyle(color: _kWhite, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)
```

Also increased the max width constraint from 120 to 180 to accommodate longer text like "All Organizations (3)".

## Display Examples

### Scenario 1: Single Organization
- **Display**: "Abra E-Logistics"

### Scenario 2: All Organizations Selected (with entity name)
- **Display**: "Abra Group (All 3 Orgs)"

### Scenario 3: All Organizations Selected (without entity name)
- **Display**: "All Organizations (3)"

### Scenario 4: Multiple Specific Organizations (with entity name)
- **Display**: "Abra Group (2 Orgs)"

### Scenario 5: Multiple Specific Organizations (without entity name)
- **Display**: "2 Organizations"

## Files Modified

1. `Billing_frontend/billing_frontend/lib/features/billing/billing_main_shell.dart`
   - Added `_selectedOrgIds` state variable
   - Created `_orgLabel` computed property
   - Updated `_loadSession()` to load selected org IDs
   - Changed display to use `_orgLabel` instead of `_orgName`
   - Increased max width constraint for org chip

## Testing

1. **Single Organization Mode**:
   - Login with a user who has access to only one organization
   - Verify the organization name is displayed correctly

2. **Multi-Organization Mode - All Selected**:
   - Login with a user who has access to multiple organizations
   - Click the organization switcher
   - Select "All Organizations"
   - Click "Apply"
   - Verify the header shows "All Organizations (X)" or "Entity Name (All X Orgs)"

3. **Multi-Organization Mode - Multiple Selected**:
   - Click the organization switcher
   - Select 2 or more specific organizations (not "All")
   - Click "Apply"
   - Verify the header shows "X Organizations" or "Entity Name (X Orgs)"

4. **Multi-Organization Mode - Single Selected**:
   - Click the organization switcher
   - Select only one organization
   - Click "Apply"
   - Verify the header shows that organization's name

## Benefits

1. **Clear Context**: Users can immediately see which organizations they're viewing
2. **Entity Branding**: When an entity name is set, it's prominently displayed
3. **Consistent Pattern**: Follows the same pattern as the branch selector
4. **Better UX**: No confusion about what data is being displayed
