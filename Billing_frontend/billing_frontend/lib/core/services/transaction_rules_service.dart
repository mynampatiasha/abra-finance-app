// ============================================================================
// TRANSACTION RULES SERVICE
// ============================================================================
// File: lib/core/services/transaction_rules_service.dart
// ============================================================================

import 'api_service.dart';

class TransactionRulesService {
  final ApiService _api = ApiService();

  Future<List<TransactionRuleModel>> getRules({String? accountId}) async {
    final q = <String, String>{};
    if (accountId != null) q['accountId'] = accountId;
    final res = await _api.get('/api/finance/transaction-rules', queryParams: q);
    if (res['success'] == true) {
      return (res['data'] as List).map((j) => TransactionRuleModel.fromJson(j)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createRule(Map<String, dynamic> data) =>
      _api.post('/api/finance/transaction-rules', body: data);

  Future<Map<String, dynamic>> updateRule(String id, Map<String, dynamic> data) =>
      _api.put('/api/finance/transaction-rules/$id', body: data);

  Future<bool> deleteRule(String id) async {
    final res = await _api.delete('/api/finance/transaction-rules/$id');
    return res['success'] == true;
  }

  Future<bool> toggleRule(String id) async {
    final res = await _api.patch('/api/finance/transaction-rules/$id/toggle', body: {});
    return res['success'] == true;
  }

  Future<Map<String, dynamic>> reorderRules(List<String> orderedIds) =>
      _api.post('/api/finance/transaction-rules/reorder', body: {'orderedIds': orderedIds});

  Future<List<Map<String, dynamic>>> testRule({
    required Map<String, dynamic> rule,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final res = await _api.post('/api/finance/transaction-rules/test', body: {
      'rule':         rule,
      'transactions': transactions,
    });
    if (res['success'] == true) return List<Map<String, dynamic>>.from(res['data']);
    return [];
  }
}

class TransactionRuleModel {
  final String  id;
  final String? accountId;
  final String  name;
  final String  description;
  final bool    isActive;
  final int     priority;
  final List<RuleCondition> conditions;
  final RuleAction          action;
  final int     matchCount;
  final DateTime? lastMatchAt;

  TransactionRuleModel({
    required this.id,
    this.accountId,
    required this.name,
    required this.description,
    required this.isActive,
    required this.priority,
    required this.conditions,
    required this.action,
    required this.matchCount,
    this.lastMatchAt,
  });

  factory TransactionRuleModel.fromJson(Map<String, dynamic> j) => TransactionRuleModel(
    id:          j['_id'] ?? j['id'] ?? '',
    accountId:   j['accountId']?.toString(),
    name:        j['name'] ?? '',
    description: j['description'] ?? '',
    isActive:    j['isActive'] ?? true,
    priority:    j['priority'] ?? 0,
    conditions:  (j['conditions'] as List? ?? [])
        .map((c) => RuleCondition.fromJson(c))
        .toList(),
    action:      RuleAction.fromJson(j['action'] ?? {}),
    matchCount:  j['matchCount'] ?? 0,
    lastMatchAt: j['lastMatchAt'] != null ? DateTime.tryParse(j['lastMatchAt']) : null,
  );

  Map<String, dynamic> toJson() => {
    'name':        name,
    'description': description,
    'isActive':    isActive,
    'priority':    priority,
    'conditions':  conditions.map((c) => c.toJson()).toList(),
    'action':      action.toJson(),
    if (accountId != null) 'accountId': accountId,
  };
}

class RuleCondition {
  final String field;    // description | amount | transactionType | referenceNumber | location
  final String operator; // contains | equals | greater_than | less_than | starts_with
  final String value;

  RuleCondition({required this.field, required this.operator, required this.value});

  factory RuleCondition.fromJson(Map<String, dynamic> j) => RuleCondition(
    field:    j['field']    ?? '',
    operator: j['operator'] ?? 'contains',
    value:    j['value']    ?? '',
  );

  Map<String, dynamic> toJson() => {'field': field, 'operator': operator, 'value': value};
}

class RuleAction {
  final String  type;           // expense | deposit | transfer | exclude
  final String? coaAccountId;
  final String? coaAccountName;
  final String? vendorName;
  final String? customerName;
  final String? toAccountId;
  final bool    autoApprove;
  final String? notes;

  RuleAction({
    required this.type,
    this.coaAccountId,
    this.coaAccountName,
    this.vendorName,
    this.customerName,
    this.toAccountId,
    required this.autoApprove,
    this.notes,
  });

  factory RuleAction.fromJson(Map<String, dynamic> j) => RuleAction(
    type:           j['type']           ?? 'expense',
    coaAccountId:   j['coaAccountId']?.toString(),
    coaAccountName: j['coaAccountName'],
    vendorName:     j['vendorName'],
    customerName:   j['customerName'],
    toAccountId:    j['toAccountId']?.toString(),
    autoApprove:    j['autoApprove']    ?? true,
    notes:          j['notes'],
  );

  Map<String, dynamic> toJson() => {
    'type':        type,
    'autoApprove': autoApprove,
    if (coaAccountId  != null) 'coaAccountId':  coaAccountId,
    if (coaAccountName!= null) 'coaAccountName':coaAccountName,
    if (vendorName    != null) 'vendorName':    vendorName,
    if (customerName  != null) 'customerName':  customerName,
    if (toAccountId   != null) 'toAccountId':   toAccountId,
    if (notes         != null) 'notes':         notes,
  };
}
