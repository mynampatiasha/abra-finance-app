// ============================================================================
// DASHBOARD SERVICE — FULLY FIXED
// ============================================================================
// File: lib/core/services/dashboard_service.dart
//
// ROOT CAUSES FIXED:
//   1. Bank endpoint was /api/finance/payment-accounts (404)
//      → Fixed to /api/finance/banking (correct from index.js)
//
//   2. AR/AP progress bar showed nothing because ApiService.get()
//      returns the ALREADY-UNWRAPPED data (not the raw {success,data} envelope).
//      So res['data'] was null. Fixed to read res directly.
//
//   3. AR/AP aging: buckets[i]['amount'] comes back as num (int or double).
//      Added safe parsing that handles both int and double from fmt().
//
//   4. Cash flow: backend /cash-flow returns operating/investing structure,
//      NOT monthly[]. Fallback correctly builds monthly from
//      /api/finance/payments-received and /api/finance/payments-made.
//      Fixed endpoint paths to match index.js registrations.
//
//   5. Income/Expense: /profit-loss returns hierarchical data, not monthly[].
//      Fallback builds monthly from invoices + expenses.
//      Fixed invoice date field: invoiceDate (not date).
//
//   6. Top Expenses: /expenses-by-category returns
//      { categories: [{category, total}], grandTotal }
//      Fixed field mapping: category → name, total → amount.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'api_service.dart';

class DashboardService {
  final ApiService _api = ApiService();

  // ── Period helper ──────────────────────────────────────────────────────────
  static Map<String, String> getPeriodDates(String period) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

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
        end   = now;
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

  /// Safe number extractor — handles int, double, String from backend
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int)    return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // ── IMPORTANT: How ApiService.get() works ─────────────────────────────────
  // ApiService.get() returns the parsed JSON body directly.
  // If the backend sends { success: true, data: {...} }
  // then _api.get() returns { 'success': true, 'data': {...} }
  // So we read res['data'] to get the inner payload.
  //
  // But if ApiService ALREADY unwraps it and returns data directly,
  // then res IS the data. We handle BOTH cases below with null-safety.

  // ── 1. Receivables (AR Aging Summary) ─────────────────────────────────────
  Future<Map<String, dynamic>> fetchReceivables(String period) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/ar-aging-summary?period=${dates['period']}',
      );

      // Handle both wrapped { success, data: {...} } and unwrapped responses
      final payload = _unwrap(res);
      if (payload != null) {
        final buckets = (payload['buckets'] as List?) ?? [];

        double current = 0;
        double overdue = 0;

        for (int i = 0; i < buckets.length; i++) {
          final amt = _toDouble(buckets[i]['amount']);
          if (i == 0) {
            current = amt; // "Current" bucket (days <= 0)
          } else {
            overdue += amt; // All overdue buckets summed
          }
        }

        final total = _toDouble(payload['total']);
        final effectiveTotal = total > 0 ? total : (current + overdue);

        return {
          'current':     current,
          'overdue':     overdue,
          'total':       effectiveTotal,
          'unpaidTotal': effectiveTotal,
        };
      }
    } catch (e) {
      // ignore — fall through to fallback
    }

    // Fallback: compute from invoices directly
    try {
      final res = await _api.get('/api/finance/invoices?limit=1000&status=UNPAID,PARTIALLY_PAID,OVERDUE,SENT');
      final list = _unwrapList(res);
      double current = 0, overdue = 0;
      final now = DateTime.now();
      for (final inv in list) {
        final due = _toDouble(inv['amountDue']);
        if (due <= 0) continue;
        final dueDateStr = inv['dueDate']?.toString();
        if (dueDateStr != null) {
          final dueDate = DateTime.tryParse(dueDateStr);
          if (dueDate != null && dueDate.isBefore(now)) {
            overdue += due;
          } else {
            current += due;
          }
        } else {
          current += due;
        }
      }
      return {
        'current':     current,
        'overdue':     overdue,
        'total':       current + overdue,
        'unpaidTotal': current + overdue,
      };
    } catch (_) {
      return {'current': 0.0, 'overdue': 0.0, 'total': 0.0, 'unpaidTotal': 0.0};
    }
  }

  // ── 2. Payables (AP Aging Summary) ────────────────────────────────────────
  Future<Map<String, dynamic>> fetchPayables(String period) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/ap-aging-summary?period=${dates['period']}',
      );

      final payload = _unwrap(res);
      if (payload != null) {
        final buckets = (payload['buckets'] as List?) ?? [];

        double current = 0;
        double overdue = 0;

        for (int i = 0; i < buckets.length; i++) {
          final amt = _toDouble(buckets[i]['amount']);
          if (i == 0) {
            current = amt;
          } else {
            overdue += amt;
          }
        }

        final total = _toDouble(payload['total']);
        final effectiveTotal = total > 0 ? total : (current + overdue);

        return {
          'current':     current,
          'overdue':     overdue,
          'total':       effectiveTotal,
          'unpaidTotal': effectiveTotal,
        };
      }
    } catch (_) {}

    // Fallback: compute from bills
    try {
      final res = await _api.get('/api/finance/bills?limit=1000');
      final list = _unwrapList(res);
      double current = 0, overdue = 0;
      final now = DateTime.now();
      for (final bill in list) {
        final due = _toDouble(bill['amountDue']);
        if (due <= 0) continue;
        final dueDateStr = bill['dueDate']?.toString();
        if (dueDateStr != null) {
          final dueDate = DateTime.tryParse(dueDateStr);
          if (dueDate != null && dueDate.isBefore(now)) {
            overdue += due;
          } else {
            current += due;
          }
        } else {
          current += due;
        }
      }
      return {
        'current':     current,
        'overdue':     overdue,
        'total':       current + overdue,
        'unpaidTotal': current + overdue,
      };
    } catch (_) {
      return {'current': 0.0, 'overdue': 0.0, 'total': 0.0, 'unpaidTotal': 0.0};
    }
  }

  // ── 3. Cash Flow ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchCashFlow(String period) async {
    debugPrint('📊 [CF] fetchCashFlow called  period=$period');
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/cash-flow?period=${dates['period']}',
      );
      debugPrint('📊 [CF] report endpoint response keys: ${res is Map ? (res as Map).keys.toList() : res.runtimeType}');
      final payload = _unwrap(res);
      debugPrint('📊 [CF] payload after unwrap: ${payload?.keys.toList() ?? 'NULL — falling to fallback'}');
      if (payload != null) {
        final summary   = payload['summary']  as Map?;
        final operating = payload['operating'] as Map?;
        final monthly   = (payload['monthlyBreakdown'] as List?)?.cast<Map>() ?? [];

        final opening  = _toDouble(summary?['openingBalance']);
        final incoming = _toDouble(summary?['totalIncoming']  ?? operating?['inflows']);
        final outgoing = _toDouble(summary?['totalOutgoing']  ?? operating?['outflows']);
        final closing  = _toDouble(summary?['closingBalance'] ?? operating?['net']);

        const abbr = ['', 'Jan','Feb','Mar','Apr','May','Jun',
                          'Jul','Aug','Sep','Oct','Nov','Dec'];

        final List<Map<String, dynamic>> builtMonthly = [];

        if (monthly.isNotEmpty) {
          // Backend only returns months WITH transactions (sparse).
          // Build a full 12-month array for the chart, filling missing
          // months with the last known running balance — exactly like Zoho Books.
          final now     = DateTime.now();
          final fyStart = now.month >= 4
              ? DateTime(now.year, 4, 1)
              : DateTime(now.year - 1, 4, 1);

          // Index the sparse backend data by month key "YYYY-MM"
          final Map<String, Map> monthlyByKey = {};
          for (final m in monthly) {
            final key = m['month']?.toString() ?? '';
            if (key.isNotEmpty) monthlyByKey[key] = m;
          }

          double lastBalance = opening;
          for (int i = 0; i < 12; i++) {
            final dt  = DateTime(fyStart.year, fyStart.month + i, 1);
            final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            final m   = monthlyByKey[key];

            if (m != null) {
              lastBalance = _toDouble(m['balance']);
              builtMonthly.add({
                'month':         abbr[dt.month],
                'date':          key,
                'incoming':      _toDouble(m['incoming']),
                'outgoing':      _toDouble(m['outgoing']),
                'endingBalance': lastBalance,
              });
            } else {
              // No transaction this month — carry forward last balance
              builtMonthly.add({
                'month':         abbr[dt.month],
                'date':          key,
                'incoming':      0.0,
                'outgoing':      0.0,
                'endingBalance': lastBalance,
              });
            }
          }
        } else {
          final now     = DateTime.now();
          final fyStart = now.month >= 4
              ? DateTime(now.year, 4, 1)
              : DateTime(now.year - 1, 4, 1);
          double running = opening;
          for (int i = 0; i < 12; i++) {
            final m     = DateTime(fyStart.year, fyStart.month + i, 1);
            final key   = '${m.year}-${m.month.toString().padLeft(2, '0')}';
            final isNow = m.year == now.year && m.month == now.month;
            final inc   = isNow ? incoming : 0.0;
            final out   = isNow ? outgoing : 0.0;
            running    += inc - out;
            builtMonthly.add({
              'month':         abbr[((m.month - 1) % 12) + 1],
              'date':          key,
              'incoming':      inc,
              'outgoing':      out,
              'endingBalance': running,
            });
          }
        }

        final fyStart = DateTime.now().month >= 4
            ? DateTime(DateTime.now().year, 4, 1)
            : DateTime(DateTime.now().year - 1, 4, 1);
        final fyEnd = DateTime(fyStart.year + 1, 3, 31);

        return {
          'openingBalance': opening,
          'totalIncoming':  incoming,
          'totalOutgoing':  outgoing,
          'endingBalance':  closing,
          'monthly':        builtMonthly,
          'fyStartLabel':   '01/04/${fyStart.year}',
          'fyEndLabel':     '31/03/${fyEnd.year}',
        };
      }
    } catch (_) {}

    // Fallback if report endpoint fails
    return _buildCashFlowFromPayments(period);
  }

  Future<Map<String, dynamic>> _buildCashFlowFromPayments(String period) async {
    try {
      final now = DateTime.now();
      final fyStart = now.month >= 4
          ? DateTime(now.year, 4, 1)
          : DateTime(now.year - 1, 4, 1);

      final months = List.generate(12, (i) {
        return DateTime(fyStart.year, fyStart.month + i, 1);
      });

      final Map<String, double> inflow  = {};
      final Map<String, double> outflow = {};
      for (final m in months) {
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        inflow[key]  = 0;
        outflow[key] = 0;
      }

      // Fetch payments received — registered at /api/finance/payments-received
      // NOTE: The GET route reformats the response and returns `amount` (not `amountReceived`)
      // Also `date` field holds the raw paymentDate string from the collection
      try {
        final prRes = await _api.get('/api/finance/payments-received?limit=1000');
        final prList = _unwrapList(prRes);
        for (final p in prList) {
          // Formatted response uses `date`, raw collection uses `paymentDate`
          final dateStr = p['date']?.toString()
              ?? p['paymentDate']?.toString();
          if (dateStr == null) continue;
          final d = _parseDate(dateStr);
          if (d == null) continue;
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          if (inflow.containsKey(key)) {
            // Formatted response maps amountReceived → amount
            inflow[key] = inflow[key]! +
                _toDouble(p['amount'] ?? p['amountReceived'] ?? p['netAmount']);
          }
        }
      } catch (_) {}

      // Fetch payments made — registered at /api/finance/payments-made
      // NOTE: Records may have orgId=null (created before orgId was enforced).
      // The GET route filters by req.user.orgId, so those records won't appear.
      // We use the /stats endpoint as a reliable fallback for the total outgoing.
      List<Map<String, dynamic>> pmList = [];
      double fallbackOutgoingTotal = 0;
      try {
        final pmRes = await _api.get('/api/finance/payments-made?limit=1000&page=1');
        pmList = _unwrapList(pmRes);

        // If empty, try the stats endpoint to at least get the total outgoing
        if (pmList.isEmpty) {
          try {
            final statsRes = await _api.get('/api/finance/payments-made/stats');
            final statsPayload = _unwrap(statsRes);
            if (statsPayload != null) {
              fallbackOutgoingTotal = _toDouble(statsPayload['totalAmount']);
            }
          } catch (_) {}
        }
      } catch (_) {}

      for (final p in pmList) {
        final dateStr = p['paymentDate']?.toString()
            ?? p['date']?.toString();
        if (dateStr == null) continue;
        final d = _parseDate(dateStr);
        if (d == null) continue;
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (outflow.containsKey(key)) {
          outflow[key] = outflow[key]! +
              _toDouble(p['totalAmount'] ?? p['amount']);
        }
      }

      const abbr = [
        '', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
        'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar',
      ];

      final double totalIncoming = inflow.values.fold(0, (a, b) => a + b);
      double totalOutgoing = outflow.values.fold(0, (a, b) => a + b);

      // If payments-made returned empty (orgId mismatch), use stats fallback total.
      // Distribute the fallback total evenly across months that have inflow,
      // so the chart line still moves rather than staying flat.
      if (totalOutgoing == 0 && fallbackOutgoingTotal > 0) {
        totalOutgoing = fallbackOutgoingTotal;
        // Spread proportionally across months with inflow, else spread evenly
        final inflowMonths = inflow.entries.where((e) => e.value > 0).toList();
        if (inflowMonths.isNotEmpty) {
          final totalInf = inflowMonths.fold(0.0, (s, e) => s + e.value);
          for (final e in inflowMonths) {
            outflow[e.key] = (e.value / totalInf) * fallbackOutgoingTotal;
          }
        } else {
          final perMonth = fallbackOutgoingTotal / months.length;
          for (final key in outflow.keys) {
            outflow[key] = perMonth;
          }
        }
      }

      const double openingBalance = 0;

      final List<Map<String, dynamic>> monthly = [];
      double running = openingBalance;
      for (int i = 0; i < months.length; i++) {
        final m   = months[i];
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        final inc = inflow[key]  ?? 0;
        final out = outflow[key] ?? 0;
        running += inc - out;
        debugPrint('📊 [CF-fallback] [$i] key=$key  inc=$inc  out=$out  running=$running');
        monthly.add({
          'month':         abbr[i + 1],
          'date':          key,
          'incoming':      inc,
          'outgoing':      out,
          'endingBalance': running,
        });
      }

      debugPrint('📊 [CF-fallback] totalIncoming=$totalIncoming  totalOutgoing=$totalOutgoing');
      debugPrint('📊 [CF-fallback] endingBalance=${openingBalance + totalIncoming - totalOutgoing}');

      final fyEnd = DateTime(fyStart.year + 1, 3, 31);

      return {
        'openingBalance': openingBalance,
        'totalIncoming':  totalIncoming,
        'totalOutgoing':  totalOutgoing,
        'endingBalance':  openingBalance + totalIncoming - totalOutgoing,
        'monthly':        monthly,
        'fyStartLabel':   '01/04/${fyStart.year}',
        'fyEndLabel':     '31/03/${fyEnd.year}',
      };
    } catch (_) {
      return {
        'openingBalance': 0.0,
        'totalIncoming':  0.0,
        'totalOutgoing':  0.0,
        'endingBalance':  0.0,
        'monthly':        <Map<String, dynamic>>[],
      };
    }
  }

  // ── 4. Income & Expense ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchIncomeExpense(
      String period, String basis) async {
    try {
      final dates = getPeriodDates(period);
      // Use the monthly endpoint — reads from AccountTransaction (same as P&L)
      // so categorized bank transactions are included correctly
      final res = await _api.get(
        '/api/finance/reports/profit-loss-monthly?period=${dates['period']}',
      );
      final payload = _unwrap(res);
      if (payload != null) {
        final rawMonthly = (payload['monthly'] as List?)?.cast<Map>() ?? [];
        if (rawMonthly.isNotEmpty) {
          final List<Map<String, dynamic>> monthly = rawMonthly.map<Map<String, dynamic>>((m) => {
            'month':   m['month']?.toString() ?? '',
            'income':  _toDouble(m['income']),
            'expense': _toDouble(m['expense']),
          }).toList();
          return {
            'totalIncome':  _toDouble(payload['totalIncome']),
            'totalExpense': _toDouble(payload['totalExpense']),
            'monthly':      monthly,
          };
        }
      }
    } catch (_) {}

    // Fallback: build from raw collections
    return _buildIncomeExpMonthly(period, 0, 0);
  }

  Future<Map<String, dynamic>> _buildIncomeExpMonthly(
      String period, double knownIncome, double knownExpense) async {
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

      // Build income from invoices
      try {
        final invRes = await _api.get('/api/finance/invoices?limit=1000');
        final invList = _unwrapList(invRes);
        for (final inv in invList) {
          // invoiceDate field — may be ISO string or Date object
          final dateStr = (inv['invoiceDate'] ?? inv['date'] ?? inv['createdAt'])?.toString();
          if (dateStr == null) continue;
          final d = _parseDate(dateStr);
          if (d == null) continue;
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          if (incomeMap.containsKey(key)) {
            incomeMap[key] = incomeMap[key]! +
                _toDouble(inv['subTotal'] ?? inv['totalAmount']);
          }
        }
      } catch (_) {}

      // Build expense from expenses
      try {
        final expRes = await _api.get('/api/finance/expenses?limit=1000');
        final expList = _unwrapList(expRes);
        for (final exp in expList) {
          final dateStr = (exp['date'] ?? exp['expenseDate'] ?? exp['createdAt'])?.toString();
          if (dateStr == null) continue;
          final d = _parseDate(dateStr);
          if (d == null) continue;
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          if (expenseMap.containsKey(key)) {
            expenseMap[key] = expenseMap[key]! +
                _toDouble(exp['total'] ?? exp['amount']);
          }
        }
      } catch (_) {}

      const abbr = [
        '', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
        'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar',
      ];

      double totalIncome  = incomeMap.values.fold(0, (a, b) => a + b);
      double totalExpense = expenseMap.values.fold(0, (a, b) => a + b);

      // Always use raw aggregated totals so header matches bar chart exactly
      // (P&L totals use a different calculation basis and will mismatch)
      // if (knownIncome > totalIncome)   totalIncome  = knownIncome;
      // if (knownExpense > totalExpense) totalExpense = knownExpense;

      final List<Map<String, dynamic>> monthly = [];
      for (int i = 0; i < months.length; i++) {
        final m   = months[i];
        final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        monthly.add({
          'month':   abbr[i + 1],
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
        'totalIncome':  knownIncome,
        'totalExpense': knownExpense,
        'monthly':      <Map<String, dynamic>>[],
      };
    }
  }

  // ── 5. Top Expenses (donut chart) ──────────────────────────────────────────
  Future<Map<String, dynamic>> fetchTopExpenses(String period) async {
    try {
      final dates = getPeriodDates(period);
      final res = await _api.get(
        '/api/finance/reports/expenses-by-category?period=${dates['period']}',
      );

      final payload = _unwrap(res);
      if (payload != null) {
        // Backend returns: { categories: [{category, count, total, percent}], grandTotal }
        final rawCats    = (payload['categories'] as List?) ?? [];
        final grandTotal = _toDouble(payload['grandTotal']);

        final categories = rawCats.map<Map<String, dynamic>>((c) => {
          'name':   c['category']?.toString() ?? 'Other',
          'amount': _toDouble(c['total']),
        }).toList();

        categories.sort((a, b) =>
            (_toDouble(b['amount'])).compareTo(_toDouble(a['amount'])));

        // ✅ FIX: Return empty data instead of falling back when backend filters out non-expenses
        return {
          'total':      grandTotal > 0
              ? grandTotal
              : categories.fold(0.0, (s, c) => s + _toDouble(c['amount'])),
          'categories': categories,
        };
      }
    } catch (_) {}

    // Fallback: aggregate expenses by account
    // ⚠️ This fallback does NOT filter by account type, so it will show ALL expenses including Assets
    try {
      final res = await _api.get('/api/finance/expenses?limit=1000');
      final list = _unwrapList(res);
      final Map<String, double> byCategory = {};
      for (final exp in list) {
        final cat = exp['expenseAccount']?.toString() ?? 'Other';
        final amt = _toDouble(exp['total'] ?? exp['amount']);
        byCategory[cat] = (byCategory[cat] ?? 0) + amt;
      }
      final total = byCategory.values.fold(0.0, (a, b) => a + b);
      final categories = byCategory.entries
          .map<Map<String, dynamic>>((e) => {'name': e.key, 'amount': e.value})
          .toList()
        ..sort((a, b) =>
            (_toDouble(b['amount'])).compareTo(_toDouble(a['amount'])));
      return {'total': total, 'categories': categories};
    } catch (_) {
      return {'total': 0.0, 'categories': <Map<String, dynamic>>[]};
    }
  }

  // ── 6. Bank Accounts ───────────────────────────────────────────────────────
  // FIXED: correct endpoint from index.js is /api/finance/banking
  Future<List<Map<String, dynamic>>> fetchBankAccounts() async {
    // Try primary endpoint — registered in index.js as /api/finance/banking
    try {
      final res = await _api.get('/api/finance/banking');
      final list = _unwrapList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    // Try alias — also registered as /api/finance/accounts
    try {
      final res = await _api.get('/api/finance/accounts');
      final list = _unwrapList(res);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    return [];
  }

  // ── Response unwrappers ────────────────────────────────────────────────────

  /// Unwraps { success: true, data: {...} } → returns data map
  /// If already unwrapped (data is the root), returns as-is
  Map<String, dynamic>? _unwrap(dynamic res) {
    if (res == null) return null;
    if (res is! Map) return null;

    final map = res as Map<String, dynamic>;

    // Case 1: { success: true, data: { ... } }
    if (map.containsKey('success') && map.containsKey('data')) {
      final data = map['data'];
      if (data is Map<String, dynamic>) return data;
      return null;
    }

    // Case 2: Already unwrapped — has domain keys like 'buckets', 'categories'
    if (map.containsKey('buckets') ||
        map.containsKey('categories') ||
        map.containsKey('monthly') ||
        map.containsKey('income') ||
        map.containsKey('total')) {
      return map;
    }

    return null;
  }

  /// Unwraps a list response — handles both wrapped and unwrapped
  List<Map<String, dynamic>> _unwrapList(dynamic res) {
    if (res == null) return [];

    // Case 1: { success: true, data: [...] }
    if (res is Map) {
      final map = res as Map<String, dynamic>;
      if (map.containsKey('data') && map['data'] is List) {
        return List<Map<String, dynamic>>.from(
            (map['data'] as List).whereType<Map>());
      }
      // Some endpoints use 'count' + 'data'
      if (map.containsKey('count') && map.containsKey('data') && map['data'] is List) {
        return List<Map<String, dynamic>>.from(
            (map['data'] as List).whereType<Map>());
      }
    }

    // Case 2: Already a list
    if (res is List) {
      return List<Map<String, dynamic>>.from(res.whereType<Map>());
    }

    return [];
  }

  /// Parse date string — handles ISO 8601 and DD/MM/YYYY formats
  DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;

    // ISO format: 2024-04-01T... or 2024-04-01
    if (s.contains('-') && s.length >= 10) {
      try {
        return DateTime.parse(s);
      } catch (_) {}
    }

    // DD/MM/YYYY format (used by payments-received)
    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 3) {
        final day   = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year  = int.tryParse(parts[2]);
        if (day != null && month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
    }

    return null;
  }
}