// ============================================================================
// NEW MANUAL JOURNAL PAGE
// ============================================================================
// File: lib/screens/billing/pages/new_manual_journal.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/manual_journal_service.dart';
import '../../../../core/services/chart_of_account_service.dart';
import '../../../../app/config/api_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const Color _kNavyDark  = Color(0xFF0F172A);
const Color _kNavy      = Color(0xFF1E3A5F);
const Color _kAccent    = Color(0xFF2563EB);
const Color _kNavyLight = Color(0xFF3B82F6);

// ── Mutable line item for form state ──────────────────────────────────────────

class _MutableLine {
  String accountId   = '';
  String accountName = '';
  String accountCode = '';
  String description = '';
  String? contactId;
  String? contactName;
  String? contactType;
  double debit       = 0;
  double credit      = 0;

  _MutableLine();

  JournalLineItem toLineItem() => JournalLineItem(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    accountId: accountId,
    accountName: accountName,
    accountCode: accountCode,
    description: description,
    contactId: contactId,
    contactName: contactName,
    contactType: contactType,
    debit: debit,
    credit: credit,
  );
}

// ── Contact model ─────────────────────────────────────────────────────────────

class _Contact {
  final String id;
  final String name;
  final String type; // 'vendor' | 'customer'

  _Contact({required this.id, required this.name, required this.type});
}

// ============================================================================
// MAIN WIDGET
// ============================================================================

class NewManualJournalPage extends StatefulWidget {
  final String? journalId;
  const NewManualJournalPage({Key? key, this.journalId}) : super(key: key);

  @override
  State<NewManualJournalPage> createState() => _NewManualJournalPageState();
}

class _NewManualJournalPageState extends State<NewManualJournalPage> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isSaving  = false;

  // Header fields
  final _journalNumCtrl   = TextEditingController();
  final _referenceCtrl    = TextEditingController();
  final _notesCtrl        = TextEditingController();
  DateTime _date          = DateTime.now();
  String _reportingMethod = 'Accrual and Cash';
  String _currency        = 'INR';

  // Line items
  final List<_MutableLine> _lines = [];

  // Totals
  double _totalDebit  = 0;
  double _totalCredit = 0;
  double _difference  = 0;

  // COA accounts dropdown
  List<ChartOfAccount> _accounts = [];
  bool _accountsLoading = true;

  // Contacts (vendors + customers combined)
  List<_Contact> _contacts = [];
  bool _contactsLoading = true;

  // Templates
  List<JournalTemplate> _templates = [];

  final _reportingMethods = ['Accrual and Cash', 'Accrual Only', 'Cash Only'];
  final _currencies       = ['INR', 'USD', 'EUR', 'GBP', 'AED'];

  @override
  void initState() {
    super.initState();
    _addLine();
    _addLine(); // Start with 2 lines
    _loadDropdowns();
    if (widget.journalId != null) _loadJournal();
  }

  @override
  void dispose() {
    _journalNumCtrl.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadDropdowns() async {
    try {
      final results = await Future.wait([
        ChartOfAccountService.getAccounts(limit: 500, isActive: true),
        _fetchContacts(),
        ManualJournalService.getTemplates(),
      ]);
      if (mounted) {
        setState(() {
          _accounts        = (results[0] as CoaListResult).accounts;
          _contacts        = results[1] as List<_Contact>;
          _templates       = results[2] as List<JournalTemplate>;
          _accountsLoading = false;
          _contactsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _accountsLoading = false; _contactsLoading = false; });
    }
  }

  Future<List<_Contact>> _fetchContacts() async {
    final prefs  = await SharedPreferences.getInstance();
    final token  = prefs.getString('jwt_token') ?? '';
    final headers = {'Authorization': 'Bearer $token', 'Accept': 'application/json'};

    final List<_Contact> contacts = [];

    // Fetch vendors
    try {
      final vRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/vendors?limit=500'),
        headers: headers,
      );
      if (vRes.statusCode == 200) {
        final data = jsonDecode(vRes.body)['data'];
        final list = (data is List) ? data : (data['vendors'] ?? []);
        for (final v in list) {
          contacts.add(_Contact(id: v['_id'] ?? '', name: v['vendorName'] ?? '', type: 'vendor'));
        }
      }
    } catch (_) {}

    // Fetch customers
    try {
      final cRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/customers?limit=500'),
        headers: headers,
      );
      if (cRes.statusCode == 200) {
        final data = jsonDecode(cRes.body)['data'];
        final list = (data is List) ? data : (data['customers'] ?? []);
        for (final c in list) {
          final name = c['customerDisplayName'] ?? c['vendorName'] ?? '';
          contacts.add(_Contact(id: c['_id'] ?? '', name: name, type: 'customer'));
        }
      }
    } catch (_) {}

    return contacts;
  }

  Future<void> _loadJournal() async {
    setState(() => _isLoading = true);
    try {
      final journal = await ManualJournalService.getJournal(widget.journalId!);
      _journalNumCtrl.text = journal.journalNumber;
      _referenceCtrl.text  = journal.referenceNumber;
      _notesCtrl.text      = journal.notes;
      setState(() {
        _date            = journal.date;
        _reportingMethod = journal.reportingMethod;
        _currency        = journal.currency;
        _lines.clear();
        for (final item in journal.lineItems) {
          final line = _MutableLine()
            ..accountId   = item.accountId
            ..accountName = item.accountName
            ..accountCode = item.accountCode
            ..description = item.description
            ..contactId   = item.contactId
            ..contactName = item.contactName
            ..contactType = item.contactType
            ..debit       = item.debit
            ..credit      = item.credit;
          _lines.add(line);
        }
        _isLoading = false;
      });
      _calculate();
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load journal: $e');
    }
  }

  // ── Line management ────────────────────────────────────────────────────────

  void _addLine() => setState(() => _lines.add(_MutableLine()));

  void _removeLine(int i) {
    if (_lines.length <= 1) return;
    setState(() { _lines.removeAt(i); _calculate(); });
  }

  void _calculate() {
    setState(() {
      _totalDebit  = _lines.fold(0, (s, l) => s + l.debit);
      _totalCredit = _lines.fold(0, (s, l) => s + l.credit);
      _difference  = double.parse((_totalDebit - _totalCredit).toStringAsFixed(2));
    });
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  void _applyTemplate(JournalTemplate t) {
    _notesCtrl.text      = t.notes;
    setState(() {
      _reportingMethod = t.reportingMethod;
      _currency        = t.currency;
      _lines.clear();
      for (final item in t.lineItems) {
        final line = _MutableLine()
          ..accountId   = item.accountId
          ..accountName = item.accountName
          ..accountCode = item.accountCode
          ..description = item.description
          ..debit       = item.debit
          ..credit      = item.credit;
        _lines.add(line);
      }
      if (_lines.isEmpty) { _lines.add(_MutableLine()); _lines.add(_MutableLine()); }
    });
    _calculate();
  }

  Future<void> _saveAsTemplate() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save as Template'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Template name', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ManualJournalService.saveTemplate({
        'templateName': name,
        'notes': _notesCtrl.text,
        'reportingMethod': _reportingMethod,
        'currency': _currency,
        'lineItems': _lines.map((l) => l.toLineItem().toJson()).toList(),
      });
      _showSuccess('Template "$name" saved');
      final templates = await ManualJournalService.getTemplates();
      setState(() => _templates = templates);
    } catch (e) { _showError('Failed to save template: $e'); }
  }

  // ── Validate ───────────────────────────────────────────────────────────────

  bool _validateForm() {
    final validLines = _lines.where((l) => l.accountId.isNotEmpty).toList();
    if (validLines.isEmpty) { _showError('Add at least one line item with an account'); return false; }
    for (final line in validLines) {
      if (line.debit == 0 && line.credit == 0) {
        _showError('Every line must have either Debit or Credit amount'); return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _buildBody(String status) {
    final validLines = _lines.where((l) => l.accountId.isNotEmpty).toList();
    return {
      if (_journalNumCtrl.text.isNotEmpty) 'journalNumber': _journalNumCtrl.text.trim(),
      'date':            _date.toIso8601String(),
      'referenceNumber': _referenceCtrl.text.trim(),
      'notes':           _notesCtrl.text.trim(),
      'reportingMethod': _reportingMethod,
      'currency':        _currency,
      'status':          status,
      'lineItems':       validLines.map((l) => l.toLineItem().toJson()).toList(),
    };
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _saveDraft() async {
    if (!_validateForm()) return;
    setState(() => _isSaving = true);
    try {
      final body = _buildBody('Draft');
      ManualJournal journal;
      if (widget.journalId != null) {
        journal = await ManualJournalService.updateJournal(widget.journalId!, body);
      } else {
        journal = await ManualJournalService.createJournal(body);
      }
      _showSuccess('${journal.journalNumber} saved as Draft');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { _showError('Failed to save: $e'); }
    finally { setState(() => _isSaving = false); }
  }

  Future<void> _saveAndPublish() async {
    if (!_validateForm()) return;
    if (_difference.abs() > 0.01) {
      _showError('Debit (₹${_totalDebit.toStringAsFixed(2)}) must equal Credit (₹${_totalCredit.toStringAsFixed(2)})\nDifference: ₹${_difference.toStringAsFixed(2)}');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish Journal'),
        content: const Text('Publishing will post all entries to Chart of Accounts. This action posts to the general ledger immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isSaving = true);
    try {
      ManualJournal journal;
      final body = _buildBody('Draft');
      if (widget.journalId != null) {
        journal = await ManualJournalService.updateJournal(widget.journalId!, body);
      } else {
        journal = await ManualJournalService.createJournal(body);
      }
      journal = await ManualJournalService.publishJournal(journal.id);
      _showSuccess('${journal.journalNumber} published and posted to Chart of Accounts ✅');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally { setState(() => _isSaving = false); }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: LayoutBuilder(builder: (_, cs) {
                final isWide = cs.maxWidth > 850;
                if (isWide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: _buildMainScroll()),
                    Container(
                      width: 300,
                      color: Colors.white,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          _buildTemplatesSection(),
                          const Divider(height: 24),
                          _buildTotalsSection(),
                          const SizedBox(height: 20),
                          _buildActionButtons(),
                        ]),
                      ),
                    ),
                  ]);
                }
                return SingleChildScrollView(
                  child: Column(children: [
                    _buildMainScroll(),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        _buildTemplatesSection(),
                        const Divider(height: 24),
                        _buildTotalsSection(),
                        const SizedBox(height: 20),
                        _buildActionButtons(),
                      ]),
                    ),
                  ]),
                );
              }),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_kNavyDark, _kNavy, _kAccent],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          widget.journalId != null ? 'Edit Manual Journal' : 'New Manual Journal',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveDraft,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save Draft'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndPublish,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.publish, size: 18),
            label: Text(_isSaving ? 'Saving…' : 'Save & Publish'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );

  Widget _buildMainScroll() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildHeaderSection(),
      const SizedBox(height: 20),
      _buildLineItemsSection(),
      const SizedBox(height: 20),
    ]),
  );

  // ── Header Section ─────────────────────────────────────────────────────────

  Widget _buildHeaderSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Journal Details', Icons.receipt_long),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final row1 = [
          // Journal Number
          Expanded(child: TextFormField(
            controller: _journalNumCtrl,
            decoration: _inputDec('Journal #', 'Auto-generated', Icons.tag),
          )),
          const SizedBox(width: 16),
          // Date
          Expanded(child: InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context,
                  initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (d != null) setState(() => _date = d);
            },
            child: InputDecorator(
              decoration: _inputDec('Date *', '', Icons.calendar_today),
              child: Text(DateFormat('dd MMM yyyy').format(_date)),
            ),
          )),
        ];
        final row2 = [
          Expanded(child: TextFormField(
            controller: _referenceCtrl,
            decoration: _inputDec('Reference #', 'Optional', Icons.numbers),
          )),
          const SizedBox(width: 16),
          Expanded(child: DropdownButtonFormField<String>(
            value: _reportingMethod,
            decoration: _inputDec('Reporting Method', '', Icons.analytics_outlined),
            items: _reportingMethods.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setState(() => _reportingMethod = v!),
          )),
        ];
        if (isWide) {
          return Column(children: [
            Row(children: row1), const SizedBox(height: 14),
            Row(children: row2), const SizedBox(height: 14),
            Row(children: [
              SizedBox(width: 180, child: DropdownButtonFormField<String>(
                value: _currency,
                decoration: _inputDec('Currency', '', Icons.currency_rupee),
                items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _currency = v!),
              )),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(
                controller: _notesCtrl,
                decoration: _inputDec('Notes', 'Journal description…', Icons.note_alt_outlined),
                maxLines: 2,
              )),
            ]),
          ]);
        }
        return Column(children: [
          ...row1, const SizedBox(height: 14),
          ...row2, const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _currency,
            decoration: _inputDec('Currency', '', Icons.currency_rupee),
            items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _currency = v!),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _notesCtrl,
            decoration: _inputDec('Notes', 'Journal description…', Icons.note_alt_outlined),
            maxLines: 2,
          ),
        ]);
      }),
    ],
  ));

  InputDecoration _inputDec(String label, String hint, IconData icon) => InputDecoration(
    labelText: label,
    hintText: hint.isEmpty ? null : hint,
    prefixIcon: Icon(icon, size: 18, color: _kNavy),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  // ── Line Items Section ─────────────────────────────────────────────────────

  Widget _buildLineItemsSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _sectionTitle('Line Items', Icons.list_alt),
        ElevatedButton.icon(
          onPressed: _addLine,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Line'),
          style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
        ),
      ]),
      const SizedBox(height: 12),
      // Table header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kNavyDark, _kNavy]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(builder: (_, cs) {
          if (cs.maxWidth < 600) {
            return const Text('LINE ITEMS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12));
          }
          return const Row(children: [
            Expanded(flex: 3, child: Text('ACCOUNT',     style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
            SizedBox(width: 8),
            Expanded(flex: 2, child: Text('DESCRIPTION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
            SizedBox(width: 8),
            Expanded(flex: 2, child: Text('CONTACT',     style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
            SizedBox(width: 8),
            SizedBox(width: 110, child: Text('DEBIT (₹)',  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
            SizedBox(width: 8),
            SizedBox(width: 110, child: Text('CREDIT (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
            SizedBox(width: 40),
          ]);
        }),
      ),
      const SizedBox(height: 8),
      // Line rows
      ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _lines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildLineRow(i),
      ),
    ],
  ));

  Widget _buildLineRow(int index) {
    final line = _lines[index];
    return LayoutBuilder(builder: (_, cs) {
      final isMobile = cs.maxWidth < 600;
      if (isMobile) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50], borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _accountDropdown(index)),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _removeLine(index)),
            ]),
            const SizedBox(height: 8),
            _descriptionField(index),
            const SizedBox(height: 8),
            _contactDropdown(index),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _amountField(index, isDebit: true)),
              const SizedBox(width: 8),
              Expanded(child: _amountField(index, isDebit: false)),
            ]),
          ]),
        );
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: _accountDropdown(index)),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: _descriptionField(index)),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: _contactDropdown(index)),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: _amountField(index, isDebit: true)),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: _amountField(index, isDebit: false)),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _removeLine(index),
        ),
      ]);
    });
  }

  Widget _accountDropdown(int index) {
    final line = _lines[index];
    if (_accountsLoading) {
      return const SizedBox(height: 48, child: Center(child: LinearProgressIndicator()));
    }
    return InkWell(
      onTap: () => _showAccountSelector(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: line.accountId.isEmpty ? Colors.grey[300]! : _kAccent.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(child: Text(
            line.accountName.isEmpty ? 'Select Account *' : line.accountName,
            style: TextStyle(
              fontSize: 13,
              color: line.accountName.isEmpty ? Colors.grey[500] : _kNavyDark,
              fontWeight: line.accountName.isEmpty ? FontWeight.normal : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          )),
          const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 18),
        ]),
      ),
    );
  }

  Future<void> _showAccountSelector(int index) async {
    final searchCtrl = TextEditingController();
    List<ChartOfAccount> filtered = List.from(_accounts);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
        title: const Text('Select Account'),
        content: SizedBox(width: 480, height: 400, child: Column(children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search accounts…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (v) => setS(() {
              filtered = v.isEmpty
                  ? List.from(_accounts)
                  : _accounts.where((a) =>
                      a.accountName.toLowerCase().contains(v.toLowerCase()) ||
                      a.accountCode.toLowerCase().contains(v.toLowerCase()) ||
                      a.accountType.toLowerCase().contains(v.toLowerCase())).toList();
            }),
          ),
          const SizedBox(height: 8),
          Expanded(child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final acc = filtered[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16, backgroundColor: _kAccent.withOpacity(0.1),
                  child: Text(acc.accountCode.isEmpty ? acc.accountType[0] : acc.accountCode[0],
                      style: TextStyle(color: _kAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                title: Text(acc.accountName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('${acc.accountType} • ${acc.accountCode}',
                    style: const TextStyle(fontSize: 11)),
                onTap: () {
                  setState(() {
                    _lines[index].accountId   = acc.id;
                    _lines[index].accountName = acc.accountName;
                    _lines[index].accountCode = acc.accountCode;
                  });
                  Navigator.pop(context);
                },
              );
            },
          )),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      )),
    );
  }

  Widget _descriptionField(int index) => TextFormField(
    initialValue: _lines[index].description,
    decoration: InputDecoration(
      hintText: 'Description…',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      isDense: true,
    ),
    style: const TextStyle(fontSize: 13),
    onChanged: (v) => _lines[index].description = v,
  );

  Widget _contactDropdown(int index) {
    final line = _lines[index];
    if (_contactsLoading) {
      return const SizedBox(height: 44, child: Center(child: LinearProgressIndicator()));
    }
    return InkWell(
      onTap: () => _showContactSelector(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          if (line.contactType != null)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: line.contactType == 'vendor' ? Colors.orange[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                line.contactType == 'vendor' ? 'V' : 'C',
                style: TextStyle(
                  fontSize: 10,
                  color: line.contactType == 'vendor' ? Colors.orange[700] : Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Expanded(child: Text(
            line.contactName ?? 'Contact (optional)',
            style: TextStyle(fontSize: 13, color: line.contactName == null ? Colors.grey[500] : _kNavyDark),
            overflow: TextOverflow.ellipsis,
          )),
          const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 18),
        ]),
      ),
    );
  }

  Future<void> _showContactSelector(int index) async {
    final searchCtrl = TextEditingController();
    List<_Contact> filtered = List.from(_contacts);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
        title: const Text('Select Contact'),
        content: SizedBox(width: 480, height: 400, child: Column(children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search vendors/customers…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (v) => setS(() {
              filtered = v.isEmpty
                  ? List.from(_contacts)
                  : _contacts.where((c) => c.name.toLowerCase().contains(v.toLowerCase())).toList();
            }),
          ),
          const SizedBox(height: 8),
          Expanded(child: ListView.builder(
            itemCount: filtered.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.clear, size: 18, color: Colors.grey),
                  title: const Text('None (clear contact)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  onTap: () {
                    setState(() {
                      _lines[index].contactId   = null;
                      _lines[index].contactName = null;
                      _lines[index].contactType = null;
                    });
                    Navigator.pop(context);
                  },
                );
              }
              final c = filtered[i - 1];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: c.type == 'vendor' ? Colors.orange[50] : Colors.blue[50],
                  child: Text(c.name[0].toUpperCase(),
                      style: TextStyle(color: c.type == 'vendor' ? Colors.orange[700] : Colors.blue[700],
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                title: Text(c.name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(c.type == 'vendor' ? 'Vendor' : 'Customer',
                    style: const TextStyle(fontSize: 11)),
                onTap: () {
                  setState(() {
                    _lines[index].contactId   = c.id;
                    _lines[index].contactName = c.name;
                    _lines[index].contactType = c.type;
                  });
                  Navigator.pop(context);
                },
              );
            },
          )),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      )),
    );
  }

  Widget _amountField(int index, {required bool isDebit}) {
    final line = _lines[index];
    return TextFormField(
      initialValue: isDebit
          ? (line.debit > 0 ? line.debit.toStringAsFixed(2) : '')
          : (line.credit > 0 ? line.credit.toStringAsFixed(2) : ''),
      decoration: InputDecoration(
        hintText: '0.00',
        labelText: isDebit ? 'Debit' : 'Credit',
        prefixText: '₹',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        isDense: true,
        labelStyle: TextStyle(color: isDebit ? Colors.red[700] : Colors.green[700], fontSize: 12),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: isDebit ? Colors.red[700] : Colors.green[700],
      ),
      onChanged: (v) {
        final val = double.tryParse(v) ?? 0;
        if (isDebit) {
          _lines[index].debit = val;
          if (val > 0) _lines[index].credit = 0;
        } else {
          _lines[index].credit = val;
          if (val > 0) _lines[index].debit = 0;
        }
        _calculate();
      },
    );
  }

  // ── Templates Section ──────────────────────────────────────────────────────

  Widget _buildTemplatesSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Templates', Icons.bookmark_outline),
      const SizedBox(height: 12),
      if (_templates.isEmpty)
        Text('No templates yet', style: TextStyle(color: Colors.grey[600], fontSize: 13))
      else
        ..._templates.map((t) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bookmark, color: _kAccent, size: 18),
          title: Text(t.templateName, style: const TextStyle(fontSize: 13)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () async {
              await ManualJournalService.deleteTemplate(t.id);
              final ts = await ManualJournalService.getTemplates();
              setState(() => _templates = ts);
            },
          ),
          onTap: () => _applyTemplate(t),
        )).toList(),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _saveAsTemplate,
        icon: const Icon(Icons.bookmark_add_outlined, size: 16),
        label: const Text('Save as Template', style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(foregroundColor: _kAccent, side: const BorderSide(color: _kAccent)),
      ),
    ],
  );

  // ── Totals Section ─────────────────────────────────────────────────────────

  Widget _buildTotalsSection() {
    final isBalanced = _difference.abs() <= 0.01;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Totals', Icons.calculate),
      const SizedBox(height: 12),
      _totalRow('Sub Total Debit',  _totalDebit,  Colors.red[700]!),
      const SizedBox(height: 6),
      _totalRow('Sub Total Credit', _totalCredit, Colors.green[700]!),
      const Divider(thickness: 2, height: 20),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isBalanced ? Colors.green[50] : Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isBalanced ? Colors.green[300]! : Colors.red[300]!),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(isBalanced ? Icons.check_circle : Icons.error,
                color: isBalanced ? Colors.green : Colors.red, size: 18),
            const SizedBox(width: 6),
            Text('Difference', style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isBalanced ? Colors.green[700] : Colors.red[700],
              fontSize: 15,
            )),
          ]),
          Text(
            '₹${_difference.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: isBalanced ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ]),
      ),
      if (!isBalanced && _totalDebit > 0) ...[
        const SizedBox(height: 8),
        Text(
          'Difference must be ₹0.00 to Publish',
          style: TextStyle(color: Colors.red[700], fontSize: 12),
        ),
      ],
    ]);
  }

  Widget _totalRow(String label, double amt, Color color) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      Text('₹${amt.toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 14)),
    ],
  );

  // ── Action Buttons ─────────────────────────────────────────────────────────

  Widget _buildActionButtons() => Column(children: [
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _isSaving ? null : _saveAndPublish,
      icon: const Icon(Icons.publish),
      label: const Text('Save & Publish'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    )),
    const SizedBox(height: 10),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: _isSaving ? null : _saveDraft,
      icon: const Icon(Icons.save_outlined),
      label: const Text('Save as Draft'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _kNavy,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: _kNavy),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    )),
    const SizedBox(height: 10),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: _isSaving ? null : () => Navigator.pop(context),
      icon: const Icon(Icons.close),
      label: const Text('Cancel'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: Colors.grey[300]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    )),
  ]);

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kNavyDark, _kNavy]),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: Colors.white, size: 16),
    ),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavyDark)),
  ]);
}