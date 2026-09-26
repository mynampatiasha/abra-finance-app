# 🚚 Finance Application

`v1.0` `Production Ready` `Flutter/Dart` `Node.js` `Enterprise` `Internal License`

> Finance & Billing Management Platform

## What is Finance Application?

Finance Application is a full-stack finance and billing management system. It combines invoicing, credit note management, account reconciliation, branch-level access control, and financial reporting in one platform, with a Flutter mobile client and a Node.js backend.

## Key Features

| Module | Status |
|---|---|
| Sales (Invoicing, Quotes, Orders) | ✅ |
| Purchases & Expenses | ✅ |
| Credit Notes & Vendor Credits | ✅ |
| Account Reconciliation | ✅ |
| Branch Access Control | ✅ |
| Financial Reporting (P&L, Balance Sheet, Cash Flow, AR Aging, etc.) | ✅ |
| Automated Backups | ✅ |

---

### 🧾 Sales

Covers the full sales cycle from quote to payment:
- Customers
- Invoices
- Recurring Invoices
- Payments Received
- Credit Notes
- Quotes
- Sales Orders
- Delivery Challans

Includes a drilldown view for outstanding receivables and unbilled shipments, so unpaid or unprocessed billing items are easy to identify and act on.

### 💰 Purchases & Expenses

Covers the vendor and spend side of the business:
- Vendors
- Vendor Credits
- Expenses
- Digital Expenses
- Fixed Assets
- Recurring Expenses
- Purchase Orders
- Bills
- Recurring Bills
- Payments Made

### 💳 Credit Notes & Vendor Credits

Covers the full credit note and vendor credit lifecycle: creation, refund handling, and account-detail behavior on refund. Includes safeguards against duplicate credit note application, so the same credit can't be applied twice by mistake.

### 🔄 Account Reconciliation

Reconciliation workflows to match transactions and financial records, with error handling for edge cases (e.g. initiate errors) built in and documented.

### 🔐 Branch Access Control

A role- and branch-based access control system, so users only see and act on data relevant to their assigned branch.

### 📊 Financial Reporting

Budget detail views with date-range filtering, plus a full suite of exportable financial reports:
- Profit & Loss (P&L)
- Balance Sheet
- Cash Flow Reports
- Expense Tracking
- Customer Balance Summary
- AR Aging (Accounts Receivable Aging)
- Invoice Data Reports

### 🔁 Automated Backups

Scheduled backup automation (via `auto_backup.js`) that safeguards financial data, with environment configuration loaded explicitly from the script directory for reliability.

---

## Architecture

```
Flutter Mobile App (Billing_frontend)
      │
Node.js Backend (Billing_backend)
      │
Billing ─ Credit Notes ─ Reconciliation ─ Branch Access ─ Reports
      │
Automated Backup Layer
```

## Billing Workflow

```
Invoice Created
     │
Unbilled Shipment / Receivables Tracking
     │
Credit Note (if applicable)
     │
Reconciliation
     │
Branch-Level Reporting
```

## Module Structure

```
Finance Application
│
├── 🧾 Sales
│   ├── Customers, Invoices, Recurring Invoices
│   ├── Payments Received
│   ├── Credit Notes, Quotes
│   ├── Sales Orders, Delivery Challans
│   └── Outstanding Receivables Drilldown
│
├── 💰 Purchases & Expenses
│   ├── Vendors, Vendor Credits
│   ├── Expenses, Digital Expenses
│   ├── Fixed Assets
│   ├── Recurring Expenses
│   └── Purchase Orders, Bills, Recurring Bills, Payments Made
│
├── 🔄 Reconciliation
│
├── 🔐 Branch Access Control
│
├── 📊 Reports
│   └── P&L, Balance Sheet, Cash Flow, AR Aging, etc.
│
└── 🔁 Automated Backups
```

## Tech Stack

**Frontend**
- Flutter (Dart)

**Backend**
- Node.js

**CI/CD & Deployment**
- Codemagic (Android & iOS builds)
- Continuous version builds deployed to the Google Play Store and Apple App Store
- Deployed on the organization's own server/domain infrastructure

## Project Structure

```
finance-app/
│
├── Billing_backend/
│   ├── api-unbilled-shipments.php
│   ├── db-financial-info.php
│   ├── shipment-reports.php
│   └── auto_backup.js
│
├── Billing_frontend/
│   └── billing_frontend/   (Flutter app)
│
├── codemagic.yaml
└── README.md
```

## 🔒 Security

API keys, database credentials, and other sensitive configuration must never be committed directly to the repository.

Never commit:
- Database credentials
- API keys
- `.env` files
- Service-account credentials

Use environment variables and the app's secure configuration mechanism for all production secrets. If a credential is accidentally exposed, revoke and replace it immediately.

## 🧪 Recommended Testing

Before deploying a new version, verify:
- Invoice creation and outstanding receivables drilldown
- Credit note creation, refund, and duplicate-prevention behavior
- Reconciliation flow, including error-handling paths
- Branch access control permissions
- Budget report date filtering
- Automated backup execution

## License

Internal Enterprise Software.
