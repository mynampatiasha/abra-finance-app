// ============================================================================
// NEW CURRENCY ADJUSTMENT PAGE
// ============================================================================
// File: lib/screens/billing/pages/new_currency_adjustment.dart
// Pattern: new_credit_note.dart structure
//   AppBar (Save Draft + Publish) | Left content | Right sidebar
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/currency_adjustment_service.dart';

// ─── colours ──────────────────────────────────────────────────────────────────
const Color _navyDark  = Color(0xFF0D1B3E);
const Color _navyMid   = Color(0xFF1e3a8a);
const Color _navyLight = Color(0xFF2463AE);
const Color _teal      = Color(0xFF0891B2);
const Color _green     = Color(0xFF27AE60);
const Color _red       = Color(0xFFE74C3C);
const Color _orange    = Color(0xFFE67E22);

// =============================================================================
class NewCurrencyAdjustmentPage extends StatefulWidget {
  final String? adjustmentId; // null = create, non-null = edit
  const NewCurrencyAdjustmentPage({ Key? key, this.adjustmentId }) : super(key: key);

  @override
  State<NewCurrencyAdjustmentPage> createState() => _NewCurrencyAdjustmentPageState();
}

class _NewCurrencyAdjustmentPageState extends State<NewCurrencyAdjustmentPage> {
  final _formKey = GlobalKey<FormState>();

  // ── state ──────────────────────────────────────────────────────────────────
  bool _isSaving    = false;
  bool _isLoading   = false;
  bool _isFetching  = false; // fetching open transactions

  // form fields
  String   _selectedCurrency = 'USD';
  double   _newRate           = 0;
  DateTime _adjustmentDate    = DateTime.now();
  String   _notes             = '';

  // loaded data
  List<String>            _currencies         = [];
  List<OpenTransaction>   _openTransactions   = [];
  List<_LinePreview>      _lineItems          = [];

  // controllers
  final _rateCtrl  = TextEditingController();
  final _notesCtrl = TextEditingController();

  // existing adjustment (edit mode)
  CurrencyAdjustment? _existingAdj;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
    if (widget.adjustmentId != null) _loadExisting();
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadCurrencies() async {
    try {
      final list = await CurrencyAdjustmentService.getSupportedCurrencies();
      if (mounted) setState(() { _currencies = list; if (!list.contains(_selectedCurrency)) _selectedCurrency = list.isNotEmpty ? list[0] : 'USD'; });
    } catch (_) {}
  }

  Future<void> _loadExisting() async {
    setState(() => _isLoading = true);
    try {
      final adj = await CurrencyAdjustmentService.getAdjustment(widget.adjustmentId!);
      if (!mounted) return;
      setState(() {
        _existingAdj       = adj;
        _selectedCurrency  = adj.currency;
        _newRate           = adj.newExchangeRate;
        _rateCtrl.text     = adj.newExchangeRate.toString();
        _adjustmentDate    = adj.adjustmentDate;
        _notes             = adj.notes;
        _notesCtrl.text    = adj.notes;
        _lineItems         = adj.lineItems.map((l) => _LinePreview.fromLine(l)).toList();
        _isLoading         = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _isLoading = false); _showError('Failed to load: $e'); }
    }
  }

  // ── fetch open transactions ─────────────────────────────────────────────────

  Future<void> _fetchOpenTransactions() async {
    if (_selectedCurrency.isEmpty) return;
    setState(() { _isFetching = true; _lineItems = []; });
    try {
      final txns = await CurrencyAdjustmentService.getOpenTransactions(_selectedCurrency);
      if (!mounted) return;
      setState(() {
        _openTransactions = txns;
        _lineItems = txns.map((t) => _LinePreview(
          transactionType:   t.transactionType,
          transactionNumber: t.transactionNumber,
          partyName:         t.partyName,
          amountDue:         t.amountDue,
          originalRate:      t.originalRate,
          dueDate:           t.dueDate,
          status:            t.status,
          gainLoss:          _newRate > 0 ? t.calculateGainLoss(_newRate) : 0,
        )).toList();
        _isFetching = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _isFetching = false); _showError('Failed to fetch transactions: $e'); }
    }
  }

  // recalculate gain/loss when rate changes
  void _recalculate() {
    if (_newRate <= 0) return;
    setState(() {
      for (int i = 0; i < _lineItems.length; i++) {
        final t = _openTransactions.length > i ? _openTransactions[i] : null;
        if (t != null) {
          _lineItems[i] = _LinePreview(
            transactionType:   t.transactionType,
            transactionNumber: t.transactionNumber,
            partyName:         t.partyName,
            amountDue:         t.amountDue,
            originalRate:      t.originalRate,
            dueDate:           t.dueDate,
            status:            t.status,
            gainLoss:          t.calculateGainLoss(_newRate),
          );
        }
      }
    });
  }

  // ── computed totals ─────────────────────────────────────────────────────────

  double get _totalGain => _lineItems.fold(0.0, (s, l) => s + (l.gainLoss > 0 ? l.gainLoss : 0));
  double get _totalLoss => _lineItems.fold(0.0, (s, l) => s + (l.gainLoss < 0 ? l.gainLoss.abs() : 0));
  double get _netAdj    => _totalGain - _totalLoss;

  // ── validation ──────────────────────────────────────────────────────────────

  bool _validate({bool forPublish = false}) {
    if (!_formKey.currentState!.validate()) return false;
    if (_selectedCurrency.isEmpty) { _showError('Please select a currency'); return false; }
    if (_newRate <= 0)              { _showError('Please enter a valid exchange rate'); return false; }
    if (_notes.trim().isEmpty)      { _showError('Notes / reason is required'); return false; }
    if (forPublish && _lineItems.isEmpty) { _showError('No open transactions found for $_selectedCurrency. Cannot publish.'); return false; }
    return true;
  }

  // ── save draft ──────────────────────────────────────────────────────────────

  Future<void> _saveDraft() async {
    if (!_validate()) return;
    setState(() => _isSaving = true);
    try {
      final data = _buildPayload();
      if (widget.adjustmentId != null) {
        await CurrencyAdjustmentService.updateAdjustment(widget.adjustmentId!, data);
      } else {
        await CurrencyAdjustmentService.createAdjustment(data);
      }
      _showSuccess('Saved as draft');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { _showError('Failed: $e'); }
    finally { if (mounted) setState(() => _isSaving = false); }
  }

  // ── publish ─────────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (!_validate(forPublish: true)) return;

    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Publish Adjustment', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Publishing will:'),
        const SizedBox(height: 8),
        _bulletPoint('Post Exchange Gain/Loss entries to Chart of Accounts'),
        _bulletPoint('Update exchange rates on all affected transactions'),
        _bulletPoint('Auto-create an audit journal entry'),
        const SizedBox(height: 8),
        const Text('This action cannot be undone.', style: TextStyle(fontWeight: FontWeight.bold, color: _red)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white), child: const Text('Publish')),
      ],
    ));
    if (ok != true) return;

    setState(() => _isSaving = true);
    try {
      String id;
      if (widget.adjustmentId != null) {
        await CurrencyAdjustmentService.updateAdjustment(widget.adjustmentId!, _buildPayload());
        id = widget.adjustmentId!;
      } else {
        final created = await CurrencyAdjustmentService.createAdjustment(_buildPayload());
        id = created.id;
      }
      await CurrencyAdjustmentService.publishAdjustment(id);
      _showSuccess('Adjustment published and posted to COA');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { _showError('Failed: $e'); }
    finally { if (mounted) setState(() => _isSaving = false); }
  }

  Map<String, dynamic> _buildPayload() => {
    'currency':        _selectedCurrency,
    'adjustmentDate':  _adjustmentDate.toIso8601String(),
    'newExchangeRate': _newRate,
    'notes':           _notes.trim(),
  };

  Widget _bulletPoint(String text) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
    ]),
  );

  // ── snacks ──────────────────────────────────────────────────────────────────

  void _showSuccess(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: _green, behavior: SnackBarBehavior.floating));
  }

  void _showError(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: _red, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4)));
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.adjustmentId != null ? 'Edit Currency Adjustment' : 'New Currency Adjustment', style: const TextStyle(fontSize: 16)),
        backgroundColor: _navyMid, foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveDraft,
            icon: const Icon(Icons.save_outlined, color: Colors.white70, size: 18),
            label: const Text('Save as Draft', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(right: 10), child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _publish,
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.publish, size: 16),
            label: Text(_isSaving ? 'Publishing…' : 'Publish', style: const TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          )),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navyMid))
          : LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              return Form(key: _formKey, child: isWide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
                        _buildDetailsCard(),
                        const SizedBox(height: 20),
                        _buildTransactionsCard(),
                        const SizedBox(height: 20),
                      ]))),
                      Container(width: 300, color: Colors.white, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
                        _buildSummaryCard(),
                        const SizedBox(height: 16),
                        _buildHelpCard(),
                      ]))),
                    ])
                  : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
                      _buildDetailsCard(),
                      const SizedBox(height: 16),
                      _buildTransactionsCard(),
                      const SizedBox(height: 16),
                      _buildSummaryCard(),
                      const SizedBox(height: 16),
                      _buildHelpCard(),
                      const SizedBox(height: 24),
                    ])));
            }),
    );
  }

  // ── details card ──────────────────────────────────────────────────────────

  Widget _buildDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Adjustment Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
        const SizedBox(height: 16),
        Row(children: [
          // Currency
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Currency *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _currencies.contains(_selectedCurrency) ? _selectedCurrency : (_currencies.isNotEmpty ? _currencies[0] : null),
                isExpanded: true,
                icon: const Icon(Icons.expand_more),
                items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() { _selectedCurrency = v; _lineItems = []; _openTransactions = []; });
                    if (_newRate > 0) _fetchOpenTransactions();
                  }
                },
              )),
            ),
          ])),
          const SizedBox(width: 16),
          // Adjustment Date
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Adjustment Date *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _adjustmentDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (d != null) setState(() => _adjustmentDate = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.calendar_today, size: 18)),
                child: Text(DateFormat('dd MMM yyyy').format(_adjustmentDate)),
              ),
            ),
          ])),
        ]),
        const SizedBox(height: 16),
        // New Exchange Rate
        Row(children: [
          Expanded(child: TextFormField(
            controller: _rateCtrl,
            decoration: InputDecoration(
              labelText: 'New Exchange Rate *',
              hintText: 'e.g. 84.50',
              helperText: '1 $_selectedCurrency = ? INR',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.currency_exchange),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,6}'))],
            validator: (v) {
              final rate = double.tryParse(v ?? '');
              if (rate == null || rate <= 0) return 'Enter a valid rate > 0';
              return null;
            },
            onChanged: (v) {
              final rate = double.tryParse(v);
              if (rate != null && rate > 0) {
                _newRate = rate;
                _recalculate();
              }
            },
            onFieldSubmitted: (_) {
              if (_newRate > 0) _fetchOpenTransactions();
            },
          )),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.only(top: 8), child: ElevatedButton.icon(
            onPressed: _isFetching || _newRate <= 0 ? null : _fetchOpenTransactions,
            icon: _isFetching ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.search, size: 16),
            label: Text(_isFetching ? 'Fetching…' : 'Fetch Transactions'),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0, minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          )),
        ]),
        const SizedBox(height: 16),
        // Notes (required)
        TextFormField(
          controller: _notesCtrl,
          decoration: InputDecoration(
            labelText: 'Notes / Reason *',
            hintText: 'e.g. Month-end forex revaluation for Q2 2025',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.notes),
          ),
          maxLines: 3,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Notes are required' : null,
          onChanged: (v) => _notes = v,
        ),
      ]),
    );
  }

  // ── transactions card ─────────────────────────────────────────────────────

  Widget _buildTransactionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Open Transactions in $_selectedCurrency', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
          if (_lineItems.isNotEmpty) Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text('${_lineItems.length} found', style: const TextStyle(color: _teal, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Enter the rate above and click "Fetch Transactions" to see open invoices and bills.', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 16),

        if (_isFetching)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: _teal)))
        else if (_lineItems.isEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
            child: Column(children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text('No open transactions in $_selectedCurrency', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('All invoices and bills are already in INR, or none are open.', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ]),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              headingRowHeight: 44, dataRowMinHeight: 50, dataRowMaxHeight: 62,
              columnSpacing: 14, horizontalMargin: 12,
              columns: [
                const DataColumn(label: SizedBox(width: 80,  child: Text('TYPE'))),
                const DataColumn(label: SizedBox(width: 140, child: Text('REF NUMBER'))),
                const DataColumn(label: SizedBox(width: 160, child: Text('PARTY'))),
                DataColumn(label: SizedBox(width: 130, child: Text('AMT DUE ($_selectedCurrency)'))),
                const DataColumn(label: SizedBox(width: 100, child: Text('OLD RATE'))),
                const DataColumn(label: SizedBox(width: 100, child: Text('NEW RATE'))),
                const DataColumn(label: SizedBox(width: 130, child: Text('GAIN / LOSS (₹)'))),
              ],
              rows: _lineItems.map((l) {
                final fmt = NumberFormat('#,##0.00');
                return DataRow(cells: [
                  DataCell(_typeBadge(l.transactionType)),
                  DataCell(Text(l.transactionNumber, style: const TextStyle(fontWeight: FontWeight.w500))),
                  DataCell(SizedBox(width: 160, child: Text(l.partyName, overflow: TextOverflow.ellipsis))),
                  DataCell(Text(fmt.format(l.amountDue))),
                  DataCell(Text(l.originalRate.toStringAsFixed(4))),
                  DataCell(Text(_newRate > 0 ? _newRate.toStringAsFixed(4) : '—', style: const TextStyle(fontWeight: FontWeight.w500))),
                  DataCell(Text(
                    _newRate > 0 ? '${l.gainLoss >= 0 ? '+' : ''}₹${fmt.format(l.gainLoss)}' : '—',
                    style: TextStyle(fontWeight: FontWeight.w700, color: l.gainLoss >= 0 ? Colors.green[700] : Colors.red[700]),
                  )),
                ]);
              }).toList(),
            ),
          ),
      ]),
    );
  }

  Widget _typeBadge(String type) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: type == 'Invoice' ? Colors.blue[50] : Colors.orange[50], borderRadius: BorderRadius.circular(8)),
    child: Text(type, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: type == 'Invoice' ? Colors.blue[700] : Colors.orange[700])),
  );

  // ── summary card ──────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final fmt = NumberFormat('#,##0.00');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
        const SizedBox(height: 14),
        _summaryRow('Currency',        _selectedCurrency,             _teal),
        const SizedBox(height: 8),
        _summaryRow('New Rate',        _newRate > 0 ? _newRate.toStringAsFixed(4) : '—', Colors.grey[700]!),
        const SizedBox(height: 8),
        _summaryRow('Transactions',    _lineItems.length.toString(),   Colors.grey[700]!),
        const Divider(height: 24),
        _summaryRow('Total Gain',      '₹${fmt.format(_totalGain)}',  Colors.green[700]!),
        const SizedBox(height: 8),
        _summaryRow('Total Loss',      '₹${fmt.format(_totalLoss)}',  Colors.red[700]!),
        const Divider(height: 20),
        _summaryRow('Net Adjustment',  '${_netAdj >= 0 ? '+' : ''}₹${fmt.format(_netAdj)}', _netAdj >= 0 ? Colors.green[800]! : Colors.red[800]!, bold: true),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _publish,
          icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.publish, size: 16),
          label: Text(_isSaving ? 'Publishing…' : 'Publish'),
          style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        )),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: _isSaving ? null : _saveDraft,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('Save as Draft'),
          style: OutlinedButton.styleFrom(foregroundColor: _navyMid, side: const BorderSide(color: _navyMid), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        )),
      ]),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool bold = false}) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: TextStyle(fontSize: bold ? 15 : 13, color: Colors.grey[700], fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
    Text(value,  style: TextStyle(fontSize: bold ? 16 : 13, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
  ]);

  // ── help card ─────────────────────────────────────────────────────────────

  Widget _buildHelpCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _teal.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: _teal.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.info_outline, color: _teal, size: 18), const SizedBox(width: 8), const Text('How it works', style: TextStyle(fontWeight: FontWeight.bold, color: _teal))]),
        const SizedBox(height: 10),
        _helpItem('Select the foreign currency to revalue'),
        _helpItem('Enter the new exchange rate (1 FX = ? INR)'),
        _helpItem('Fetch open invoices + bills in that currency'),
        _helpItem('Review gain/loss per transaction'),
        _helpItem('Publish → posts to COA + creates audit journal'),
      ]),
    );
  }

  Widget _helpItem(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('• ', style: TextStyle(color: _teal, fontWeight: FontWeight.bold)),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.4))),
    ]),
  );
}

// =============================================================================
// HELPER MODEL — line preview for display in form
// =============================================================================

class _LinePreview {
  final String transactionType;
  final String transactionNumber;
  final String partyName;
  final double amountDue;
  final double originalRate;
  final DateTime? dueDate;
  final String status;
  double gainLoss;

  _LinePreview({
    required this.transactionType, required this.transactionNumber,
    required this.partyName, required this.amountDue,
    required this.originalRate, this.dueDate,
    required this.status, required this.gainLoss,
  });

  factory _LinePreview.fromLine(AdjustmentLineItem l) => _LinePreview(
    transactionType:   l.transactionType,
    transactionNumber: l.transactionNumber,
    partyName:         l.partyName,
    amountDue:         l.amountDue,
    originalRate:      l.originalRate,
    dueDate:           l.dueDate,
    status:            l.status,
    gainLoss:          l.gainLoss,
  );
}