import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// TRANSACTION RULES SCREEN — Full CRUD (Zoho Books pin-to-pin)
// ============================================================================
// File: lib/screens/banking/transaction_rules_screen.dart
//
// Rules auto-categorize transactions on every import.
// IF description contains "HDFC RENT" → Category = Rent, Vendor = Landlord
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/transaction_rules_service.dart';
import '../../../core/services/bank_transaction_service.dart';

const Color _navy = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green = Color(0xFF27AE60);
const Color _blue = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red = Color(0xFFE74C3C);

class TransactionRulesScreen extends StatefulWidget {
  final String? accountId;
  final String? accountName;

  const TransactionRulesScreen({Key? key, this.accountId, this.accountName})
      : super(key: key);

  @override
  State<TransactionRulesScreen> createState() => _TransactionRulesScreenState();
}

class _TransactionRulesScreenState extends State<TransactionRulesScreen> {
  final TransactionRulesService _rulesService = TransactionRulesService();
  final BankTransactionService _bankService = BankTransactionService();

  List<TransactionRuleModel> _rules = [];
  List<COAOption> _expCOAs = [];
  List<COAOption> _incCOAs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _rulesService.getRules(accountId: widget.accountId),
        _bankService.getCOAOptions('expense'),
        _bankService.getCOAOptions('income'),
      ]);
      setState(() {
        _rules = results[0] as List<TransactionRuleModel>;
        _expCOAs = results[1] as List<COAOption>;
        _incCOAs = results[2] as List<COAOption>;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B3E),
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Transaction Rules',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (widget.accountName != null)
            Text(widget.accountName!,
                style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
          const SizedBox(width: 8),
        ],
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : Column(children: [
              _buildInfoBanner(),
              Expanded(
                  child: _rules.isEmpty ? _buildEmpty() : _buildRulesList()),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRuleDialog(),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Rule',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _blue.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(Icons.auto_fix_high, color: _blue, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
          'Rules run automatically on every import. Matching transactions are categorized instantly — no manual work needed.',
          style: TextStyle(fontSize: 12, color: Colors.blue[900]),
        )),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.rule_folder_outlined, size: 72, color: Colors.grey[300]),
      const SizedBox(height: 20),
      const Text('No Rules Yet',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50))),
      const SizedBox(height: 8),
      Text('Create rules to auto-categorize transactions on import.',
          style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => _showRuleDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Create First Rule'),
        style: ElevatedButton.styleFrom(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
      ),
    ]));
  }

  Widget _buildRulesList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: _rules.length,
      onReorder: (oldIdx, newIdx) async {
        if (newIdx > oldIdx) newIdx--;
        setState(() {
          final r = _rules.removeAt(oldIdx);
          _rules.insert(newIdx, r);
        });
        await _rulesService.reorderRules(_rules.map((r) => r.id).toList());
      },
      itemBuilder: (_, i) => _buildRuleCard(_rules[i], i),
    );
  }

  Widget _buildRuleCard(TransactionRuleModel rule, int idx) {
    final typeColor = _typeColor(rule.action.type);
    final typeIcon = _typeIcon(rule.action.type);

    return Container(
      key: ValueKey(rule.id),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: rule.isActive
                ? typeColor.withOpacity(0.25)
                : Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color:
                rule.isActive ? typeColor.withOpacity(0.05) : Colors.grey[50],
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12), topRight: Radius.circular(12)),
          ),
          child: Row(children: [
            // Drag handle
            Icon(Icons.drag_indicator, color: Colors.grey[400], size: 20),
            const SizedBox(width: 8),
            // Priority badge
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: rule.isActive ? typeColor : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Center(
                  child: Text('${idx + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(rule.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: rule.isActive
                            ? const Color(0xFF2C3E50)
                            : Colors.grey[500],
                      )),
                  if (rule.description.isNotEmpty)
                    Text(rule.description,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
            // Active toggle
            Switch(
              value: rule.isActive,
              activeColor: typeColor,
              onChanged: (_) async {
                await _rulesService.toggleRule(rule.id);
                _loadAll();
              },
            ),
            // Actions
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[500]),
              onSelected: (v) async {
                if (v == 'edit') _showRuleDialog(rule: rule);
                if (v == 'delete') _deleteRule(rule);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ])),
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ])),
              ],
            ),
          ]),
        ),

        // Conditions + Action
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Conditions
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Icon(Icons.filter_list, size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text('IF',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[500])),
                  ]),
                  const SizedBox(height: 4),
                  ...rule.conditions.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_fieldLabel(c.field)} ${_opLabel(c.operator)} "${c.value}"',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      )),
                ])),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              width: 1,
              height: 40,
              color: Colors.grey[200],
            ),
            // Action
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Icon(Icons.arrow_forward,
                        size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text('THEN',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[500])),
                  ]),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: typeColor.withOpacity(0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(typeIcon, size: 12, color: typeColor),
                      const SizedBox(width: 4),
                      Flexible(
                          child: Text(
                        _actionLabel(rule.action),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: typeColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                  ),
                  if (rule.matchCount > 0) ...[
                    const SizedBox(height: 4),
                    Text('Applied ${rule.matchCount} times',
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ],
                ])),
          ]),
        ),
      ]),
    );
  }

  // =========================================================================
  //  RULE DIALOG
  // =========================================================================

  void _showRuleDialog({TransactionRuleModel? rule}) {
    final nameCtrl = TextEditingController(text: rule?.name ?? '');
    final descCtrl = TextEditingController(text: rule?.description ?? '');
    final vendorCtrl =
        TextEditingController(text: rule?.action.vendorName ?? '');
    final notesCtrl = TextEditingController(text: rule?.action.notes ?? '');

    // Conditions
    final conditions = rule?.conditions
            .map((c) => _EditCondition(
                  field: c.field,
                  operator: c.operator,
                  value: c.value,
                  ctrl: TextEditingController(text: c.value),
                ))
            .toList() ??
        [
          _EditCondition(
              field: 'description',
              operator: 'contains',
              value: '',
              ctrl: TextEditingController())
        ];

    // Action
    String actionType = rule?.action.type ?? 'expense';
    COAOption? selCOA = rule?.action.coaAccountId != null
        ? (_expCOAs + _incCOAs)
            .where((c) => c.id == rule!.action.coaAccountId)
            .firstOrNull
        : null;
    bool autoApprove = rule?.action.autoApprove ?? true;
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final allCOAs = actionType == 'expense' ? _expCOAs : _incCOAs;

        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 580,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1B3E),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16)),
                ),
                child: Row(children: [
                  const Icon(Icons.rule, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(rule == null ? 'Create Rule' : 'Edit Rule',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
              ),

              Flexible(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name
                          TextFormField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Rule Name *',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              hintText: 'e.g. HDFC Rent Auto-categorize',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: descCtrl,
                            decoration: InputDecoration(
                              labelText: 'Description (optional)',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // CONDITIONS section
                          _sectionHeader('CONDITIONS',
                              'All conditions must match (AND logic)'),
                          const SizedBox(height: 10),
                          ...conditions.asMap().entries.map((e) =>
                              _conditionRow(e.value, conditions, setS, e.key)),
                          TextButton.icon(
                            onPressed: () => setS(() => conditions.add(
                                  _EditCondition(
                                      field: 'description',
                                      operator: 'contains',
                                      value: '',
                                      ctrl: TextEditingController()),
                                )),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Condition'),
                            style: TextButton.styleFrom(foregroundColor: _navy),
                          ),
                          const SizedBox(height: 20),

                          // ACTION section
                          _sectionHeader(
                              'ACTION', 'What to do when conditions match'),
                          const SizedBox(height: 10),

                          // Action type
                          Row(children: [
                            ...[
                              'expense',
                              'deposit',
                              'exclude'
                            ].map((t) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(_typeLabel(t),
                                        style: const TextStyle(fontSize: 12)),
                                    selected: actionType == t,
                                    onSelected: (_) => setS(() {
                                      actionType = t;
                                      selCOA = null;
                                    }),
                                    selectedColor: _typeColor(t),
                                    labelStyle: TextStyle(
                                        color: actionType == t
                                            ? Colors.white
                                            : null),
                                  ),
                                )),
                          ]),
                          const SizedBox(height: 12),

                          if (actionType != 'exclude') ...[
                            DropdownButtonFormField<COAOption>(
                              decoration: InputDecoration(
                                labelText: actionType == 'expense'
                                    ? 'Expense Category *'
                                    : 'Income Category *',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              isExpanded: true,
                              value: selCOA,
                              items: allCOAs
                                  .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(
                                            '${c.accountCode} - ${c.accountName}',
                                            overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (v) => setS(() => selCOA = v),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: vendorCtrl,
                              decoration: InputDecoration(
                                labelText: actionType == 'expense'
                                    ? 'Vendor (optional)'
                                    : 'Customer (optional)',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: notesCtrl,
                              decoration: InputDecoration(
                                labelText: 'Notes (optional)',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Auto-approve toggle
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    const Text('Auto-approve',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        autoApprove
                                            ? 'Transactions are categorized automatically'
                                            : 'Transactions need manual confirmation',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600])),
                                  ])),
                              Switch(
                                value: autoApprove,
                                activeColor: _green,
                                onChanged: (v) => setS(() => autoApprove = v),
                              ),
                            ]),
                          ),
                        ],
                      ))),

              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border:
                      const Border(top: BorderSide(color: Color(0xFFEEF2F7))),
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16)),
                ),
                child: Row(children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: TextStyle(color: Colors.grey[600]))),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              _showError('Rule name required');
                              return;
                            }
                            if (conditions.isEmpty ||
                                conditions
                                    .every((c) => c.ctrl.text.trim().isEmpty)) {
                              _showError('Add at least one condition');
                              return;
                            }
                            if (actionType != 'exclude' && selCOA == null) {
                              _showError('Select a category for the action');
                              return;
                            }
                            setS(() => saving = true);
                            try {
                              final data = {
                                'name': nameCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'isActive': true,
                                'conditions': conditions
                                    .where((c) => c.ctrl.text.trim().isNotEmpty)
                                    .map((c) => {
                                          'field': c.field,
                                          'operator': c.operator,
                                          'value': c.ctrl.text.trim()
                                        })
                                    .toList(),
                                'action': {
                                  'type': actionType,
                                  'coaAccountId': selCOA?.id,
                                  'coaAccountName': selCOA?.accountName,
                                  'vendorName': vendorCtrl.text.trim().isEmpty
                                      ? null
                                      : vendorCtrl.text.trim(),
                                  'notes': notesCtrl.text.trim().isEmpty
                                      ? null
                                      : notesCtrl.text.trim(),
                                  'autoApprove': autoApprove,
                                },
                                if (widget.accountId != null)
                                  'accountId': widget.accountId,
                              };

                              if (rule == null) {
                                await _rulesService.createRule(data);
                              } else {
                                await _rulesService.updateRule(rule.id, data);
                              }

                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              _loadAll();
                              _showSuccess(rule == null
                                  ? 'Rule created'
                                  : 'Rule updated');
                            } catch (e) {
                              setS(() => saving = false);
                              _showError('Failed: $e');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(rule == null ? 'Create Rule' : 'Update Rule',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: _navy)),
      Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ]);
  }

  Widget _conditionRow(
      _EditCondition c, List<_EditCondition> all, StateSetter setS, int idx) {
    const fields = [
      'description',
      'amount',
      'transactionType',
      'referenceNumber',
      'location',
      'merchantName'
    ];
    const ops = [
      'contains',
      'not_contains',
      'equals',
      'not_equals',
      'greater_than',
      'less_than',
      'starts_with',
      'ends_with'
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!)),
      child: Row(children: [
        Expanded(
            child: DropdownButtonFormField<String>(
          decoration: const InputDecoration(
              labelText: 'Field',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          value: c.field,
          items: fields
              .map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(_fieldLabel(f),
                      style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) => setS(() => c.field = v ?? 'description'),
        )),
        const SizedBox(width: 6),
        Expanded(
            child: DropdownButtonFormField<String>(
          decoration: const InputDecoration(
              labelText: 'Operator',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          value: c.operator,
          items: ops
              .map((o) => DropdownMenuItem(
                  value: o,
                  child:
                      Text(_opLabel(o), style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) => setS(() => c.operator = v ?? 'contains'),
        )),
        const SizedBox(width: 6),
        Expanded(
            child: TextFormField(
          controller: c.ctrl,
          decoration: const InputDecoration(
              labelText: 'Value',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          style: const TextStyle(fontSize: 12),
        )),
        if (all.length > 1)
          IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: _red, size: 18),
              onPressed: () => setS(() => all.removeAt(idx))),
      ]),
    );
  }

  Future<void> _deleteRule(TransactionRuleModel rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Rule'),
        content: Text('Delete "${rule.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _rulesService.deleteRule(rule.id);
    _loadAll();
    _showSuccess('Rule deleted');
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _typeLabel(String t) {
    const m = {
      'expense': 'Expense',
      'deposit': 'Deposit',
      'transfer': 'Transfer',
      'exclude': 'Exclude'
    };
    return m[t] ?? t;
  }

  Color _typeColor(String t) {
    const m = {
      'expense': _red,
      'deposit': _green,
      'transfer': _blue,
      'exclude': Colors.grey
    };
    return m[t] ?? _navy;
  }

  IconData _typeIcon(String t) {
    const m = {
      'expense': Icons.arrow_upward,
      'deposit': Icons.arrow_downward,
      'transfer': Icons.compare_arrows,
      'exclude': Icons.block
    };
    return m[t] ?? Icons.auto_fix_high;
  }

  String _actionLabel(RuleAction a) {
    switch (a.type) {
      case 'expense':
        return '${a.type.toUpperCase()}: ${a.coaAccountName ?? "—"}${a.vendorName != null ? " | ${a.vendorName}" : ""}';
      case 'deposit':
        return '${a.type.toUpperCase()}: ${a.coaAccountName ?? "—"}${a.customerName != null ? " | ${a.customerName}" : ""}';
      case 'exclude':
        return 'EXCLUDE from books';
      default:
        return a.type.toUpperCase();
    }
  }

  String _fieldLabel(String f) {
    const m = {
      'description': 'Description',
      'amount': 'Amount',
      'transactionType': 'Type',
      'referenceNumber': 'Reference',
      'location': 'Location',
      'merchantName': 'Merchant'
    };
    return m[f] ?? f;
  }

  String _opLabel(String o) {
    const m = {
      'contains': 'contains',
      'not_contains': "doesn't contain",
      'equals': '=',
      'not_equals': '≠',
      'greater_than': '>',
      'less_than': '<',
      'starts_with': 'starts with',
      'ends_with': 'ends with'
    };
    return m[o] ?? o;
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  void _showError(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }
}

// ── Editable condition state ────────────────────────────────────────────────

class _EditCondition {
  String field;
  String operator;
  String value;
  final TextEditingController ctrl;

  _EditCondition(
      {required this.field,
      required this.operator,
      required this.value,
      required this.ctrl});
}

extension _ListExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
