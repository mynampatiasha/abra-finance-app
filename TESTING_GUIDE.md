# Multi-Organization Selection - Testing Guide

## ✅ Backend is Ready to Test NOW

The backend implementation is complete and backward compatible. You can test it immediately using API tools like Postman or curl.

---

## 🧪 Backend Testing (Ready Now)

### Test 1: Default Behavior (Backward Compatible)
**Scenario:** Existing behavior - single org mode

**Request:**
```bash
GET /api/finance/invoices
Headers:
  Authorization: Bearer <your_jwt_token>
  x-branch-ids: ALL
  # NO x-org-ids header (backward compatible)
```

**Expected Result:**
- ✅ Returns invoices from current org only (orgId from JWT token)
- ✅ Same behavior as before (no breaking changes)

---

### Test 2: All Organizations
**Scenario:** View data from all organizations user belongs to

**Request:**
```bash
GET /api/finance/invoices
Headers:
  Authorization: Bearer <your_jwt_token>
  x-org-ids: ALL
  x-branch-ids: ALL
```

**Expected Result:**
- ✅ Returns invoices from ALL organizations user belongs to
- ✅ Each invoice has orgId field showing which org it belongs to

---

### Test 3: Specific Organizations
**Scenario:** View data from Org A and Org B only

**Request:**
```bash
GET /api/finance/invoices
Headers:
  Authorization: Bearer <your_jwt_token>
  x-org-ids: <orgId1>,<orgId2>
  x-branch-ids: ALL
```

**Expected Result:**
- ✅ Returns invoices from orgId1 and orgId2 only
- ✅ No invoices from other organizations

---

### Test 4: Unauthorized Organization Access
**Scenario:** User tries to access org they don't belong to

**Request:**
```bash
GET /api/finance/invoices
Headers:
  Authorization: Bearer <your_jwt_token>
  x-org-ids: <unauthorized_orgId>
  x-branch-ids: ALL
```

**Expected Result:**
- ✅ Returns 403 error
- ✅ Error code: `ORG_ACCESS_DENIED`
- ✅ Message: "You do not have access to the requested organization(s)."

---

### Test 5: Multi-Org with Branch Restrictions
**Scenario:** User with branch restrictions across multiple orgs

**Setup:**
- User has access to Branch A in Org 1
- User has access to Branch B in Org 2

**Request:**
```bash
GET /api/finance/invoices
Headers:
  Authorization: Bearer <your_jwt_token>
  x-org-ids: ALL
  x-branch-ids: ALL
```

**Expected Result:**
- ✅ Returns invoices from Branch A (Org 1) and Branch B (Org 2) only
- ✅ Branch restrictions enforced across all selected orgs

---

### Test 6: Reports Across Multiple Orgs
**Scenario:** Generate consolidated report for multiple organizations

**Request:**
```bash
GET /api/finance/reports/profit-loss
Headers:
  Authorization: Bearer <your_jwt_token>
  x-org-ids: <orgId1>,<orgId2>
  x-branch-ids: ALL
```

**Expected Result:**
- ✅ Returns P&L data aggregated from orgId1 and orgId2
- ✅ Data grouped by organization (if report supports it)

---

## 🎨 Frontend Testing (Waiting for UI Implementation)

### Current Status:
- ✅ Storage layer ready (can save/load org selection)
- ✅ Auth service ready (sends x-org-ids header)
- ❌ UI not implemented yet (no org selector page)

### Manual Testing (For Developers):

You can manually test the frontend storage layer using Flutter DevTools:

```dart
// Save selected orgs
await FinanceSecureStorage.saveSelectedOrgIds(['org1', 'org2']);

// Get org header
final header = await FinanceSecureStorage.getOrgHeader();
print(header); // Should print: "org1,org2"

// Check multi-org mode
final isMulti = await FinanceSecureStorage.isMultiOrgMode();
print(isMulti); // Should print: true

// Clear selection
await FinanceSecureStorage.clearOrgSelection();
```

---

## 🔍 How to Test with Postman

### Step 1: Login
```
POST /api/finance/auth/login
Body:
{
  "email": "your@email.com",
  "password": "yourpassword"
}
```

**Save the token from response.**

### Step 2: Get Your Organizations
```
GET /api/finance/auth/my-orgs
Headers:
  Authorization: Bearer <token>
```

**Note down the orgIds from response.**

### Step 3: Test Multi-Org Query
```
GET /api/finance/invoices
Headers:
  Authorization: Bearer <token>
  x-org-ids: ALL
  x-branch-ids: ALL
```

### Step 4: Test Specific Orgs
```
GET /api/finance/invoices
Headers:
  Authorization: Bearer <token>
  x-org-ids: <orgId1>,<orgId2>
  x-branch-ids: ALL
```

---

## 📊 Test Data Setup

### Create Test Scenario:

1. **Create User with Multiple Orgs:**
   - Register user
   - Create Org A
   - Create Org B
   - Add user to both orgs

2. **Create Test Data:**
   - Create invoices in Org A
   - Create invoices in Org B
   - Create bills in both orgs

3. **Test Queries:**
   - Query with `x-org-ids: ALL` → should see both orgs' data
   - Query with `x-org-ids: orgA` → should see only Org A data
   - Query with `x-org-ids: orgA,orgB` → should see both orgs' data

---

## ✅ Verification Checklist

### Backend Verification:
- [ ] Default behavior works (no x-org-ids header)
- [ ] ALL organizations mode works
- [ ] Specific organizations mode works
- [ ] Unauthorized access blocked (403 error)
- [ ] Branch restrictions enforced across orgs
- [ ] All route files updated correctly
- [ ] No syntax errors in middleware
- [ ] Backups created successfully

### Frontend Verification:
- [ ] Storage methods work correctly
- [ ] getOrgHeader() returns correct value
- [ ] isMultiOrgMode() returns correct boolean
- [ ] clearOrgSelection() clears data
- [ ] Auth service sends x-org-ids header
- [ ] No syntax errors in Dart files

---

## 🐛 Common Issues & Solutions

### Issue 1: 400 Error - Missing branch context
**Cause:** x-branch-ids header is missing
**Solution:** Always send x-branch-ids header (even if "ALL")

### Issue 2: 403 Error - Organization access denied
**Cause:** User doesn't belong to requested org
**Solution:** Check user's organizations list, only request orgs they belong to

### Issue 3: Empty results
**Cause:** No data exists in selected organizations
**Solution:** Create test data in the organizations first

### Issue 4: Duplicate data
**Cause:** Same data returned multiple times
**Solution:** Check if orgFilter is applied correctly in route

---

## 📈 Performance Testing

### Test Query Performance:

1. **Single Org (Baseline):**
   ```
   x-org-ids: <single_orgId>
   ```
   - Measure response time
   - Check database query

2. **Multiple Orgs:**
   ```
   x-org-ids: <org1>,<org2>,<org3>
   ```
   - Compare response time to baseline
   - Should use `$in` operator efficiently

3. **All Orgs:**
   ```
   x-org-ids: ALL
   ```
   - Test with user having 5+ organizations
   - Verify performance is acceptable

---

## 🎯 Success Criteria

### Backend:
- ✅ All tests pass
- ✅ No breaking changes to existing functionality
- ✅ Performance acceptable for multi-org queries
- ✅ Error handling works correctly
- ✅ Branch restrictions enforced

### Frontend:
- ✅ Storage layer works
- ✅ Headers sent correctly
- ⏳ UI implementation (pending)
- ⏳ User can select organizations (pending)
- ⏳ Navigation flow updated (pending)

---

## 📝 Test Report Template

```
Test Date: ___________
Tester: ___________

Backend Tests:
[ ] Test 1: Default Behavior - PASS/FAIL
[ ] Test 2: All Organizations - PASS/FAIL
[ ] Test 3: Specific Organizations - PASS/FAIL
[ ] Test 4: Unauthorized Access - PASS/FAIL
[ ] Test 5: Branch Restrictions - PASS/FAIL
[ ] Test 6: Reports - PASS/FAIL

Frontend Tests:
[ ] Storage Layer - PASS/FAIL
[ ] Auth Service - PASS/FAIL
[ ] UI (pending) - N/A

Issues Found:
1. ___________
2. ___________

Notes:
___________
```

---

**Ready to Test:** ✅ Backend  
**Waiting for:** 🚧 Frontend UI  
**Estimated Testing Time:** 1-2 hours for backend, 2-3 hours for frontend (once UI is ready)
