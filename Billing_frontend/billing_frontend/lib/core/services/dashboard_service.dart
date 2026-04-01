// ============================================================================
// DASHBOARD SERVICE
// ============================================================================
// File: lib/core/services/dashboard_service.dart
// Fetches all data needed for the HomeBilling dashboard
// Uses existing ApiService — no hardcoded URLs or tokens
// ============================================================================

import 'api_service.dart';

class DashboardService {
  final ApiService _api = ApiService();


  // ── Period helper ──────────────────────────────────────────────────────────
  static Map<String, String> getPeriodDates(String period) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    // Indian fiscal year: April 1 → March 31
    final fyStart = now.month >= 4
        ? DateTime(now.year, 4, 1)
        : DateTime(now.year - 1, 4, 1);
    final fyEnd = DateTime(fyStart.year + 1, 3, 31);

    switch (period) {
      case 'This Month':
        start = DateTime(now.year, now.month, 1);
        end   = DateTime(now.year, now.month + 1, 0);
        break;
      case 'Last Month':
        final lm = DateTime(now.year, now.month - 1, 1);
        start = lm;
        end   = DateTime(now.year, now.month, 0);
        break;
      case 'This Quarter':
        final q = ((now.month - 1) ~/ 3);
        start = DateTime(now.year, q * 3 + 1, 1);
        end   = DateTime(now.year, q * 3 + 3 + 1, 0);
        break;
      case 'This Fiscal Year':
        start = fyStart;
        end   = fyEnd;
        break;
      case 'Last Fiscal Year':
        start = DateTime(fyStart.year - 1, 4, 1);
        end   = DateTime(fyStart.year, 3, 31);
        break;
      default:
        start = fyStart;
        end   = fyEnd;
    }

    return {
      'fromDate': _fmt(start),
      'toDate':   _fmt(end),
      'period':   _periodParam(period),
    };
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _periodParam(String p) {
    switch (p) {
      case 'This Month':       return 'this_month';
      case 'Last Month':       return 'last_month';
      case 'This Quarter':     return 'this_quarter';
      case 'This Fiscal Year': return 'this_fy';
      case 'Last Fiscal Year': return 'last_fy';
      default:                 return 'this_fy';
    }
  }

  // ── 1. Receivables (AR Aging) ──────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchReceivables(String period) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/ar-aging?period=${dates['period']}',
      );
      if (res['success'] == true) return res['data'] ?? {};
    } catch (_) {}
    // Fallback: compute from invoices
    try {
      final res = await _api.get('/api/finance/invoices?limit=1000');
      final invoices = (res['data'] as List?) ?? [];
      double current = 0, overdue = 0;
      final now = DateTime.now();
      for (final inv in invoices) {
        final due = inv['amountDue'] ?? 0.0;
        if (due <= 0) continue;
        final dueDateStr = inv['dueDate'];
        if (dueDateStr != null) {
          final dueDate = DateTime.tryParse(dueDateStr.toString());
          if (dueDate != null && dueDate.isBefore(now)) {
            overdue += (due as num).toDouble();
          } else {
            current += (due as num).toDouble();
          }
        } else {
          current += (due as num).toDouble();
        }
      }
      return {'current': current, 'overdue': overdue};
    } catch (_) {
      return {'current': 0.0, 'overdue': 0.0};
    }
  }

  // ── 2. Payables (AP Aging) ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchPayables(String period) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/ap-aging?period=${dates['period']}',
      );
      if (res['success'] == true) return res['data'] ?? {};
    } catch (_) {}
    // Fallback: compute from bills
    try {
      final res = await _api.get('/api/finance/bills?limit=1000');
      final bills = (res['data'] as List?) ?? [];
      double current = 0, overdue = 0;
      final now = DateTime.now();
      for (final bill in bills) {
        final due = bill['amountDue'] ?? 0.0;
        if (due <= 0) continue;
        final dueDateStr = bill['dueDate'];
        if (dueDateStr != null) {
          final dueDate = DateTime.tryParse(dueDateStr.toString());
          if (dueDate != null && dueDate.isBefore(now)) {
            overdue += (due as num).toDouble();
          } else {
            current += (due as num).toDouble();
          }
        } else {
          current += (due as num).toDouble();
        }
      }
      return {'current': current, 'overdue': overdue};
    } catch (_) {
      return {'current': 0.0, 'overdue': 0.0};
    }
  }

  // ── 3. Cash Flow (monthly line chart) ─────────────────────────────────────
  Future<Map<String, dynamic>> fetchCashFlow(String period) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/cash-flow?period=${dates['period']}',
      );
      if (res['success'] == true) {
        final data = res['data'];
        if (data != null) return Map<String, dynamic>.from(data);
      }
    } catch (_) {}

    // Fallback: build monthly cash flow from payments_received + payments_made
    try {
      final now = DateTime.now();
      final fyStart = now.month >= 4
          ? DateTime(now.year, 4, 1)
          : DateTime(now.year - 1, 4, 1);

      // Build 12 monthly buckets
      final months = List.generate(12, (i) {
        final m = DateTime(fyStart.year, fyStart.month + i, 1);
        return m;
      });

      final Map<String, double> inflow  = {};
      final Map<String, double> outflow = {};
      for (final m in months) {
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        inflow[key]  = 0;
        outflow[key] = 0;
      }

      // Fetch payments received
      final prRes = await _api.get('/api/finance/payments-received?limit=1000');
      for (final p in ((prRes['data'] as List?) ?? [])) {
        final dateStr = p['paymentDate']?.toString() ?? p['date']?.toString();
        if (dateStr == null) continue;
        final d = DateTime.tryParse(dateStr);
        if (d == null) continue;
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (inflow.containsKey(key)) {
          inflow[key] = inflow[key]! + ((p['amountReceived'] ?? p['amount'] ?? 0) as num).toDouble();
        }
      }

      // Fetch payments made
      final pmRes = await _api.get('/api/finance/payments-made?limit=1000');
      for (final p in ((pmRes['data'] as List?) ?? [])) {
        final dateStr = p['paymentDate']?.toString() ?? p['date']?.toString();
        if (dateStr == null) continue;
        final d = DateTime.tryParse(dateStr);
        if (d == null) continue;
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (outflow.containsKey(key)) {
          outflow[key] = outflow[key]! + ((p['totalAmount'] ?? p['amount'] ?? 0) as num).toDouble();
        }
      }

      double openingBalance = 0;
      double totalIncoming  = inflow.values.fold(0, (a, b) => a + b);
      double totalOutgoing  = outflow.values.fold(0, (a, b) => a + b);

      // Build monthly data
      final List<Map<String, dynamic>> monthly = [];
      double runningBalance = openingBalance;
      for (final m in months) {
        final key   = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        final label = _monthLabel(m);
        final inc   = inflow[key]  ?? 0;
        final out   = outflow[key] ?? 0;
        runningBalance += inc - out;
        monthly.add({
          'month':           label,
          'date':            key,
          'incoming':        inc,
          'outgoing':        out,
          'endingBalance':   runningBalance,
        });
      }

      return {
        'openingBalance': openingBalance,
        'totalIncoming':  totalIncoming,
        'totalOutgoing':  totalOutgoing,
        'endingBalance':  openingBalance + totalIncoming - totalOutgoing,
        'monthly':        monthly,
        'fyStartLabel':   '${fyStart.day.toString().padLeft(2,'0')}/${fyStart.month.toString().padLeft(2,'0')}/${fyStart.year}',
        'fyEndLabel':     '31/03/${fyStart.year + 1}',
      };
    } catch (_) {
      return {
        'openingBalance': 0.0,
        'totalIncoming':  0.0,
        'totalOutgoing':  0.0,
        'endingBalance':  0.0,
        'monthly':        [],
      };
    }
  }

  // ── 4. Income & Expense (bar chart) ───────────────────────────────────────
  Future<Map<String, dynamic>> fetchIncomeExpense(
      String period, String basis) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/profit-loss?period=${dates['period']}&basis=${basis.toLowerCase()}',
      );
      if (res['success'] == true) {
        final data = res['data'];
        if (data != null) return Map<String, dynamic>.from(data);
      }
    } catch (_) {}

    // Fallback: compute from invoices + expenses per month
    try {
      final now = DateTime.now();
      final fyStart = now.month >= 4
          ? DateTime(now.year, 4, 1)
          : DateTime(now.year - 1, 4, 1);

      final months = List.generate(12, (i) =>
          DateTime(fyStart.year, fyStart.month + i, 1));

      final Map<String, double> incomeMap  = {};
      final Map<String, double> expenseMap = {};
      for (final m in months) {
        final k = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        incomeMap[k]  = 0;
        expenseMap[k] = 0;
      }

      // Income from invoices
      final invRes = await _api.get('/api/finance/invoices?limit=1000');
      for (final inv in ((invRes['data'] as List?) ?? [])) {
        final dateStr = inv['invoiceDate']?.toString();
        if (dateStr == null) continue;
        final d = DateTime.tryParse(dateStr);
        if (d == null) continue;
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (incomeMap.containsKey(key)) {
          incomeMap[key] = incomeMap[key]! +
              ((inv['subTotal'] ?? inv['totalAmount'] ?? 0) as num).toDouble();
        }
      }

      // Expenses
      final expRes = await _api.get('/api/finance/expenses?limit=1000');
      for (final exp in ((expRes['data'] as List?) ?? [])) {
        final dateStr = exp['date']?.toString();
        if (dateStr == null) continue;
        final d = DateTime.tryParse(dateStr);
        if (d == null) continue;
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (expenseMap.containsKey(key)) {
          expenseMap[key] = expenseMap[key]! +
              ((exp['total'] ?? exp['amount'] ?? 0) as num).toDouble();
        }
      }

      double totalIncome  = incomeMap.values.fold(0, (a, b) => a + b);
      double totalExpense = expenseMap.values.fold(0, (a, b) => a + b);

      final List<Map<String, dynamic>> monthly = [];
      for (final m in months) {
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        monthly.add({
          'month':   _monthLabel(m),
          'income':  incomeMap[key]  ?? 0,
          'expense': expenseMap[key] ?? 0,
        });
      }

      return {
        'totalIncome':  totalIncome,
        'totalExpense': totalExpense,
        'monthly':      monthly,
      };
    } catch (_) {
      return {
        'totalIncome':  0.0,
        'totalExpense': 0.0,
        'monthly':      [],
      };
    }
  }

  // ── 5. Top Expenses (donut chart) ─────────────────────────────────────────
  Future<Map<String, dynamic>> fetchTopExpenses(String period) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/expense-by-category?period=${dates['period']}',
      );
      if (res['success'] == true) {
        final data = res['data'];
        if (data != null) return Map<String, dynamic>.from(data);
      }
    } catch (_) {}

    // Fallback: aggregate expenses by account
    try {
      final res = await _api.get('/api/finance/expenses?limit=1000');
      final expenses = (res['data'] as List?) ?? [];
      final Map<String, double> byCategory = {};
      for (final exp in expenses) {
        final cat = exp['expenseAccount']?.toString() ?? 'Other';
        final amt = ((exp['total'] ?? exp['amount'] ?? 0) as num).toDouble();
        byCategory[cat] = (byCategory[cat] ?? 0) + amt;
      }
      final total = byCategory.values.fold(0.0, (a, b) => a + b);
      final categories = byCategory.entries
          .map((e) => {'name': e.key, 'amount': e.value})
          .toList()
        ..sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
      return {'total': total, 'categories': categories};
    } catch (_) {
      return {'total': 0.0, 'categories': []};
    }
  }

  // ── 6. Bank Accounts ──────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchBankAccounts() async {
    try {
      final res = await _api.get('/api/finance/payment-accounts');
      if (res['success'] == true) {
        return List<Map<String, dynamic>>.from(res['data'] ?? []);
      }
    } catch (_) {}
    try {
      final res = await _api.get('/api/finance/bank-accounts');
      if (res['success'] == true) {
        return List<Map<String, dynamic>>.from(res['data'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static String _monthLabel(DateTime m) {
    const months = [
      'Apr','May','Jun','Jul','Aug','Sep',
      'Oct','Nov','Dec','Jan','Feb','Mar'
    ];
    // Map month number to fiscal month label
    const abbr = ['','Jan','Feb','Mar','Apr','May','Jun',
                   'Jul','Aug','Sep','Oct','Nov','Dec'];
    return abbr[m.month];
  }
}
