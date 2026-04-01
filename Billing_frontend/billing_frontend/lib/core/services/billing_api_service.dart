// ============================================================================
// BILLING API SERVICE - WITH MONTHLY BREAKDOWN SUPPORT
// ============================================================================
// File: lib/core/services/billing_api_service.dart
// Features: Dashboard with monthly breakdowns for Income/Expense and Cash Flow
// ✅ UPDATED: Added balance field to MonthlyDataPoint for cumulative cash flow
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../app/config/finance_api_config.dart';
import '../../core/finance_secure_storage.dart';

class BillingApiService {
  static String get _base => FinanceApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await FinanceSecureStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _get(String path, {Map<String, String>? params}) async {
    var uri = Uri.parse('$_base$path');
    if (params != null && params.isNotEmpty) {
      uri = uri.replace(queryParameters: params);
    }
    debugPrint('📤 GET: $uri');
    final response = await http.get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 30));
    debugPrint('📥 ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw Exception(data['message'] ?? 'Request failed (${response.statusCode})');
  }

  // ============================================================================
  // DASHBOARD APIs
  // ============================================================================

  static Future<DashboardSummary> getDashboardSummary({String basis = 'accrual'}) async {
    try {
      final data = await _get('/api/finance/home/summary', params: {'basis': basis});
      return DashboardSummary.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching dashboard summary: $e');
      rethrow;
    }
  }

  static Future<ReceivablesSummary> getReceivables() async {
    try {
      final data = await _get('/api/finance/home/receivables');
      return ReceivablesSummary.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching receivables: $e');
      rethrow;
    }
  }

  static Future<PayablesSummary> getPayables() async {
    try {
      final data = await _get('/api/finance/home/payables');
      return PayablesSummary.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching payables: $e');
      rethrow;
    }
  }

  static Future<CashFlowData> getCashFlow({String period = 'fiscal_year'}) async {
    try {
      final data = await _get('/api/finance/home/cash-flow', params: {'period': period});
      return CashFlowData.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching cash flow: $e');
      rethrow;
    }
  }

  static Future<IncomeExpenseData> getIncomeExpense({
    String period = 'fiscal_year',
    String basis = 'accrual',
  }) async {
    try {
      final data = await _get('/api/finance/home/income-expense',
          params: {'period': period, 'basis': basis});
      return IncomeExpenseData.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching income and expense: $e');
      rethrow;
    }
  }

  static Future<ProjectsSummary> getProjects() async {
    try {
      final data = await _get('/api/finance/home/projects');
      return ProjectsSummary.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching projects: $e');
      rethrow;
    }
  }

  static Future<BankAccountsSummary> getBankAccounts() async {
    try {
      final data = await _get('/api/finance/home/bank-accounts');
      return BankAccountsSummary.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching bank accounts: $e');
      rethrow;
    }
  }

  static Future<AccountWatchlist> getAccountWatchlist({String basis = 'accrual'}) async {
    try {
      final data = await _get('/api/finance/home/watchlist', params: {'basis': basis});
      return AccountWatchlist.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching watchlist: $e');
      rethrow;
    }
  }

  static Future<IncomeExpenseDetail> getIncomeExpenseDetail({
    required String month,
    required String type,
    required String basis,
  }) async {
    try {
      final data = await _get('/api/finance/home/income-expense-detail',
          params: {'month': month, 'type': type, 'basis': basis});
      return IncomeExpenseDetail.fromJson(data['data']);
    } catch (e) {
      debugPrint('❌ Error fetching income/expense detail: $e');
      rethrow;
    }
  }
}

// ============================================================================
// INCOME/EXPENSE DETAIL MODELS (for detailed report screen)
// ============================================================================

/// Income/Expense Detail Report
class IncomeExpenseDetail {
  final String month;
  final String type;
  final String basis;
  final double totalAmount;
  final List<TransactionDetail> transactions;

  IncomeExpenseDetail({
    required this.month,
    required this.type,
    required this.basis,
    required this.totalAmount,
    required this.transactions,
  });

  factory IncomeExpenseDetail.fromJson(Map<String, dynamic> json) {
    return IncomeExpenseDetail(
      month: json['month'] ?? '',
      type: json['type'] ?? '',
      basis: json['basis'] ?? 'accrual',
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      transactions: (json['transactions'] as List?)
              ?.map((t) => TransactionDetail.fromJson(t))
              .toList() ??
          [],
    );
  }
}

/// Transaction Detail
class TransactionDetail {
  final DateTime date;
  final String description;
  final String reference;
  final String? customer;
  final double amount;

  TransactionDetail({
    required this.date,
    required this.description,
    required this.reference,
    this.customer,
    required this.amount,
  });

  factory TransactionDetail.fromJson(Map<String, dynamic> json) {
    return TransactionDetail(
      date: DateTime.parse(json['date']),
      description: json['description'] ?? '',
      reference: json['reference'] ?? '',
      customer: json['customer'],
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Complete Dashboard Summary
class DashboardSummary {
  final ReceivablesSummary receivables;
  final PayablesSummary payables;
  final CashFlowData cashFlow;
  final IncomeExpenseData? incomeExpense;
  final ProjectsSummary projects;
  final BankAccountsSummary bankAccounts;
  final AccountWatchlist watchlist;
  final DateTime generatedAt;

  DashboardSummary({
    required this.receivables,
    required this.payables,
    required this.cashFlow,
    this.incomeExpense,
    required this.projects,
    required this.bankAccounts,
    required this.watchlist,
    required this.generatedAt,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      receivables: ReceivablesSummary.fromJson(json['receivables']),
      payables: PayablesSummary.fromJson(json['payables']),
      cashFlow: CashFlowData.fromJson(json['cashFlow']),
      incomeExpense: json['incomeExpense'] != null 
          ? IncomeExpenseData.fromJson(json['incomeExpense'])
          : null,
      projects: ProjectsSummary.fromJson(json['projects']),
      bankAccounts: BankAccountsSummary.fromJson(json['bankAccounts']),
      watchlist: AccountWatchlist.fromJson(json['watchlist']),
      generatedAt: DateTime.parse(json['generatedAt']),
    );
  }
}

/// Receivables Summary
class ReceivablesSummary {
  final double total;
  final double current;
  final double overdue;
  final String totalFormatted;
  final String currentFormatted;
  final String overdueFormatted;
  final int invoiceCount;

  ReceivablesSummary({
    required this.total,
    required this.current,
    required this.overdue,
    required this.totalFormatted,
    required this.currentFormatted,
    required this.overdueFormatted,
    required this.invoiceCount,
  });

  factory ReceivablesSummary.fromJson(Map<String, dynamic> json) {
    return ReceivablesSummary(
      total: (json['total'] ?? 0).toDouble(),
      current: (json['current'] ?? 0).toDouble(),
      overdue: (json['overdue'] ?? 0).toDouble(),
      totalFormatted: json['totalFormatted'] ?? '₹0.00',
      currentFormatted: json['currentFormatted'] ?? '₹0.00',
      overdueFormatted: json['overdueFormatted'] ?? '₹0.00',
      invoiceCount: json['invoiceCount'] ?? 0,
    );
  }
}

/// Payables Summary
class PayablesSummary {
  final double total;
  final double current;
  final double overdue;
  final String totalFormatted;
  final String currentFormatted;
  final String overdueFormatted;
  final int billCount;

  PayablesSummary({
    required this.total,
    required this.current,
    required this.overdue,
    required this.totalFormatted,
    required this.currentFormatted,
    required this.overdueFormatted,
    required this.billCount,
  });

  factory PayablesSummary.fromJson(Map<String, dynamic> json) {
    return PayablesSummary(
      total: (json['total'] ?? 0).toDouble(),
      current: (json['current'] ?? 0).toDouble(),
      overdue: (json['overdue'] ?? 0).toDouble(),
      totalFormatted: json['totalFormatted'] ?? '₹0.00',
      currentFormatted: json['currentFormatted'] ?? '₹0.00',
      overdueFormatted: json['overdueFormatted'] ?? '₹0.00',
      billCount: json['billCount'] ?? 0,
    );
  }
}

/// ✅ Monthly Data Point (for charts) - UPDATED WITH BALANCE
class MonthlyDataPoint {
  final String month; // e.g., "Apr 2025"
  final double income;
  final double expense;
  final double incoming;
  final double outgoing;
  final double net;
  final double balance; // ✅ CUMULATIVE BALANCE FOR CASH FLOW

  MonthlyDataPoint({
    required this.month,
    this.income = 0,
    this.expense = 0,
    this.incoming = 0,
    this.outgoing = 0,
    this.net = 0,
    this.balance = 0, // ✅ NEW - Cumulative balance for Zoho Books style chart
  });

  factory MonthlyDataPoint.fromJson(Map<String, dynamic> json) {
    return MonthlyDataPoint(
      month: json['month'] ?? '',
      income: (json['income'] ?? 0).toDouble(),
      expense: (json['expense'] ?? 0).toDouble(),
      incoming: (json['incoming'] ?? 0).toDouble(),
      outgoing: (json['outgoing'] ?? 0).toDouble(),
      net: (json['net'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(), // ✅ NEW
    );
  }
}

/// Cash Flow Data (with monthly breakdown)
class CashFlowData {
  final double incoming;
  final double outgoing;
  final double openingBalance;
  final double closingBalance;
  final String incomingFormatted;
  final String outgoingFormatted;
  final String openingBalanceFormatted;
  final String closingBalanceFormatted;
  final DateTime startDate;
  final DateTime endDate;
  final String period;
  final List<MonthlyDataPoint> monthlyData; // ✅ Includes balance field

  CashFlowData({
    required this.incoming,
    required this.outgoing,
    required this.openingBalance,
    required this.closingBalance,
    required this.incomingFormatted,
    required this.outgoingFormatted,
    required this.openingBalanceFormatted,
    required this.closingBalanceFormatted,
    required this.startDate,
    required this.endDate,
    required this.period,
    this.monthlyData = const [],
  });

  factory CashFlowData.fromJson(Map<String, dynamic> json) {
    return CashFlowData(
      incoming: (json['incoming'] ?? 0).toDouble(),
      outgoing: (json['outgoing'] ?? 0).toDouble(),
      openingBalance: (json['openingBalance'] ?? 0).toDouble(),
      closingBalance: (json['closingBalance'] ?? 0).toDouble(),
      incomingFormatted: json['incomingFormatted'] ?? '₹0.00',
      outgoingFormatted: json['outgoingFormatted'] ?? '₹0.00',
      openingBalanceFormatted: json['openingBalanceFormatted'] ?? '₹0.00',
      closingBalanceFormatted: json['closingBalanceFormatted'] ?? '₹0.00',
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      period: json['period'] ?? 'fiscal_year',
      monthlyData: (json['monthlyData'] as List?)
              ?.map((item) => MonthlyDataPoint.fromJson(item))
              .toList() ??
          [],
    );
  }
}

/// Income and Expense Data (with monthly breakdown)
class IncomeExpenseData {
  final double totalIncome;
  final double totalExpense;
  final double netProfit;
  final String totalIncomeFormatted;
  final String totalExpenseFormatted;
  final String netProfitFormatted;
  final DateTime startDate;
  final DateTime endDate;
  final String period;
  final String basis; // ✅ accrual or cash
  final List<MonthlyDataPoint> monthlyData;

  IncomeExpenseData({
    required this.totalIncome,
    required this.totalExpense,
    required this.netProfit,
    required this.totalIncomeFormatted,
    required this.totalExpenseFormatted,
    required this.netProfitFormatted,
    required this.startDate,
    required this.endDate,
    required this.period,
    this.basis = 'accrual',
    this.monthlyData = const [],
  });

  factory IncomeExpenseData.fromJson(Map<String, dynamic> json) {
    return IncomeExpenseData(
      totalIncome: (json['totalIncome'] ?? 0).toDouble(),
      totalExpense: (json['totalExpense'] ?? 0).toDouble(),
      netProfit: (json['netProfit'] ?? 0).toDouble(),
      totalIncomeFormatted: json['totalIncomeFormatted'] ?? '₹0.00',
      totalExpenseFormatted: json['totalExpenseFormatted'] ?? '₹0.00',
      netProfitFormatted: json['netProfitFormatted'] ?? '₹0.00',
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      period: json['period'] ?? 'fiscal_year',
      basis: json['basis'] ?? 'accrual',
      monthlyData: (json['monthlyData'] as List?)
              ?.map((item) => MonthlyDataPoint.fromJson(item))
              .toList() ??
          [],
    );
  }
}

/// Projects Summary
class ProjectsSummary {
  final List<Project> projects;
  final int totalProjects;

  ProjectsSummary({
    required this.projects,
    required this.totalProjects,
  });

  factory ProjectsSummary.fromJson(Map<String, dynamic> json) {
    return ProjectsSummary(
      projects: (json['projects'] as List?)
              ?.map((project) => Project.fromJson(project))
              .toList() ??
          [],
      totalProjects: json['totalProjects'] ?? 0,
    );
  }
}

/// Project Model
class Project {
  final String name;
  final String status;
  final double? remaining;

  Project({
    required this.name,
    required this.status,
    this.remaining,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      remaining: json['remaining'] != null 
          ? (json['remaining'] as num).toDouble() 
          : null,
    );
  }
}

/// Bank Accounts Summary
class BankAccountsSummary {
  final List<BankAccount> accounts;
  final int totalAccounts;

  BankAccountsSummary({
    required this.accounts,
    required this.totalAccounts,
  });

  factory BankAccountsSummary.fromJson(Map<String, dynamic> json) {
    return BankAccountsSummary(
      accounts: (json['accounts'] as List?)
              ?.map((account) => BankAccount.fromJson(account))
              .toList() ??
          [],
      totalAccounts: json['totalAccounts'] ?? 0,
    );
  }
}

/// Bank Account Model
class BankAccount {
  final String name;
  final String type;
  final String? bankName;
  final double balance;
  final String balanceFormatted;

  BankAccount({
    required this.name,
    required this.type,
    this.bankName,
    required this.balance,
    required this.balanceFormatted,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      bankName: json['bankName'],
      balance: (json['balance'] ?? 0).toDouble(),
      balanceFormatted: json['balanceFormatted'] ?? '₹0.00',
    );
  }
}

/// Account Watchlist
class AccountWatchlist {
  final List<WatchlistAccount> accounts;
  final int totalAccounts;
  final String basis;

  AccountWatchlist({
    required this.accounts,
    required this.totalAccounts,
    required this.basis,
  });

  factory AccountWatchlist.fromJson(Map<String, dynamic> json) {
    return AccountWatchlist(
      accounts: (json['accounts'] as List?)
              ?.map((account) => WatchlistAccount.fromJson(account))
              .toList() ??
          [],
      totalAccounts: json['totalAccounts'] ?? 0,
      basis: json['basis'] ?? 'accrual',
    );
  }
}

/// Watchlist Account Model
class WatchlistAccount {
  final String name;
  final String type;
  final double balance;
  final String balanceFormatted;

  WatchlistAccount({
    required this.name,
    required this.type,
    required this.balance,
    required this.balanceFormatted,
  });

  factory WatchlistAccount.fromJson(Map<String, dynamic> json) {
    return WatchlistAccount(
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      balance: (json['balance'] ?? 0).toDouble(),
      balanceFormatted: json['balanceFormatted'] ?? '₹0.00',
    );
  }
}