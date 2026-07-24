import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// NEW / EDIT FIXED ASSET PAGE
// ============================================================================
// File: lib/screens/billing/pages/new_fixed_asset.dart
// ============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class NewFixedAssetPage extends StatefulWidget {
  final String baseUrl;
  final String token;
  final Map<String, dynamic>? existingAsset; // null = create mode
  const NewFixedAssetPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.existingAsset,
  });

  @override
  State<NewFixedAssetPage> createState() => _NewFixedAssetPageState();
}

class _NewFixedAssetPageState extends State<NewFixedAssetPage> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _loadingCOA = false;

  // ── Controllers ───────────────────────────────────────────────────────────
  final _assetNameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _assetCostCtrl = TextEditingController();
  final _salvageCtrl = TextEditingController();
  final _usefulLifeCtrl = TextEditingController(text: '60');
  final _depRateCtrl = TextEditingController(text: '20');
  final _notesCtrl = TextEditingController();
  final _assetAccCtrl = TextEditingController();
  final _depAccCtrl = TextEditingController();
  final _expAccCtrl = TextEditingController(text: 'Depreciation Expense');

  // ── Dropdowns ─────────────────────────────────────────────────────────────
  String _assetType = 'IT Equipment';
  String _depMethod = 'straight_line';
  String _depFrequency = 'yearly';
  String? _paidThrough;
  String _purchaseDate = DateTime.now().toIso8601String().split('T')[0];
  String _depStartDate = DateTime.now().toIso8601String().split('T')[0];

  // ── COA accounts ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _bankAccounts = [];
  List<Map<String, dynamic>> _coaAccounts = [];

  // ── Options ───────────────────────────────────────────────────────────────
  static const _assetTypes = [
    'IT Equipment',
    'Furniture & Fixtures',
    'Machinery',
    'Vehicle',
    'Building',
    'Land',
    'Office Equipment',
    'Other',
  ];
  static const _depMethods = [
    {'value': 'straight_line', 'label': 'Straight Line'},
    {'value': 'declining_balance', 'label': 'Declining Balance'},
    {'value': 'none', 'label': 'No Depreciation'},
  ];
  static const _depFreqs = [
    {'value': 'yearly', 'label': 'Yearly'},
    {'value': 'monthly', 'label': 'Monthly'},
  ];

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadCOAAccounts();
    if (widget.existingAsset != null) _populateExisting();
  }

  @override
  void dispose() {
    for (final c in [
      _assetNameCtrl,
      _descCtrl,
      _serialCtrl,
      _vendorCtrl,
      _assetCostCtrl,
      _salvageCtrl,
      _usefulLifeCtrl,
      _depRateCtrl,
      _notesCtrl,
      _assetAccCtrl,
      _depAccCtrl,
      _expAccCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _populateExisting() {
    final a = widget.existingAsset!;
    _assetNameCtrl.text = a['assetName'] ?? '';
    _descCtrl.text = a['description'] ?? '';
    _serialCtrl.text = a['serialNumber'] ?? '';
    _vendorCtrl.text = a['vendor'] ?? '';
    _assetCostCtrl.text = a['assetCost']?.toString() ?? '';
    _salvageCtrl.text = a['salvageValue']?.toString() ?? '0';
    _usefulLifeCtrl.text = a['usefulLifeMonths']?.toString() ?? '60';
    _depRateCtrl.text = a['depreciationRate']?.toString() ?? '20';
    _notesCtrl.text = a['notes'] ?? '';
    _assetAccCtrl.text = a['assetAccountName'] ?? '';
    _depAccCtrl.text = a['depreciationAccountName'] ?? '';
    _expAccCtrl.text = a['expenseAccountName'] ?? 'Depreciation Expense';
    _assetType = a['assetType'] ?? 'IT Equipment';
    _depMethod = a['depreciationMethod'] ?? 'straight_line';
    _depFrequency = a['depreciationFrequency'] ?? 'yearly';
    _purchaseDate = a['purchaseDate'] ?? _purchaseDate;
    _depStartDate = a['depreciationStartDate'] ?? _purchaseDate;
    _paidThrough = a['paidThrough'];
  }

  // ── Load COA & Bank Accounts ──────────────────────────────────────────────
  Future<void> _loadCOAAccounts() async {
    setState(() => _loadingCOA = true);
    try {
      // Load bank/payment accounts for "Paid Through"
      final bankRes = await http.get(
        Uri.parse('${widget.baseUrl}/api/finance/banking'),
        headers: _headers,
      );
      if (bankRes.statusCode == 200) {
        final data = jsonDecode(bankRes.body);
        setState(() {
          _bankAccounts = List<Map<String, dynamic>>.from(
              (data['data'] ?? data['accounts'] ?? []).map((a) => {
                    'id': a['_id'] ?? a['id'] ?? '',
                    'name': a['accountName'] ?? a['name'] ?? '',
                  }));
        });
      }
    } catch (e) {
      debugPrint('Error loading accounts: $e');
    } finally {
      setState(() => _loadingCOA = false);
    }
  }

  // ── Auto-fill account names when asset name changes ───────────────────────
  void _onAssetNameChanged(String name) {
    if (_assetAccCtrl.text.isEmpty ||
        _assetAccCtrl.text.contains('Fixed Asset')) {
      _assetAccCtrl.text = '$_assetType - $name';
    }
    if (_depAccCtrl.text.isEmpty || _depAccCtrl.text.contains('Accumulated')) {
      _depAccCtrl.text = 'Accumulated Depreciation - $name';
    }
  }

  // ── Date Picker ───────────────────────────────────────────────────────────
  Future<String?> _pickDate(String initial) async {
    final parts = initial.split('-');
    final init = parts.length == 3
        ? DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
        : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    return picked?.toIso8601String().split('T')[0];
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final body = {
        'assetName': _assetNameCtrl.text.trim(),
        'assetType': _assetType,
        'description': _descCtrl.text.trim(),
        'serialNumber': _serialCtrl.text.trim(),
        'vendor': _vendorCtrl.text.trim(),
        'purchaseDate': _purchaseDate,
        'assetCost': double.tryParse(_assetCostCtrl.text) ?? 0,
        'paidThrough': _paidThrough,
        'assetAccountName': _assetAccCtrl.text.trim(),
        'depreciationAccountName': _depAccCtrl.text.trim(),
        'expenseAccountName': _expAccCtrl.text.trim(),
        'depreciationMethod': _depMethod,
        'depreciationFrequency': _depFrequency,
        'usefulLifeMonths': int.tryParse(_usefulLifeCtrl.text) ?? 60,
        'salvageValue': double.tryParse(_salvageCtrl.text) ?? 0,
        'depreciationRate': double.tryParse(_depRateCtrl.text) ?? 20,
        'depreciationStartDate': _depStartDate,
        'notes': _notesCtrl.text.trim(),
      };

      final isEdit = widget.existingAsset != null;
      final id = widget.existingAsset?['_id'] ?? '';
      final url = isEdit
          ? '${widget.baseUrl}/api/finance/fixed-assets/$id'
          : '${widget.baseUrl}/api/finance/fixed-assets';

      final res = isEdit
          ? await http.put(Uri.parse(url),
              headers: _headers, body: jsonEncode(body))
          : await http.post(Uri.parse(url),
              headers: _headers, body: jsonEncode(body));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        _showSnack(isEdit
            ? 'Asset updated successfully'
            : 'Asset created successfully');
        if (mounted) Navigator.pop(context, true);
      } else {
        _showSnack(data['message'] ?? 'Error saving asset', error: true);
      }
    } catch (e) {
      _showSnack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg, isError: true);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingAsset != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Fixed Asset' : 'New Fixed Asset',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Save Asset'),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Basic Information', [
              _field('Asset Name *', _assetNameCtrl,
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  onChanged: _onAssetNameChanged),
              const SizedBox(height: 12),
              _dropdown<String>(
                label: 'Asset Type *',
                value: _assetType,
                items: _assetTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _assetType = v ?? _assetType),
              ),
              const SizedBox(height: 12),
              _field('Description', _descCtrl, maxLines: 2),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field('Serial Number', _serialCtrl)),
                const SizedBox(width: 12),
                Expanded(child: _field('Vendor', _vendorCtrl)),
              ]),
            ]),
            _section('Purchase Details', [
              Row(children: [
                Expanded(
                  child: _dateTile('Purchase Date', _purchaseDate,
                      onTap: () async {
                    final d = await _pickDate(_purchaseDate);
                    if (d != null) setState(() => _purchaseDate = d);
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field('Asset Cost (₹) *', _assetCostCtrl,
                      keyboardType: TextInputType.number, validator: (v) {
                    if (v?.trim().isEmpty ?? true) return 'Required';
                    if (double.tryParse(v!) == null) return 'Invalid number';
                    return null;
                  }),
                ),
              ]),
              const SizedBox(height: 12),
              // Paid Through
              _loadingCOA
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      value: _paidThrough,
                      decoration: const InputDecoration(
                        labelText: 'Paid Through (optional)',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                            value: null, child: Text('-- Select Account --')),
                        ..._bankAccounts.map((a) => DropdownMenuItem<String>(
                              value: a['id'] as String,
                              child: Text(a['name'] as String),
                            )),
                      ],
                      onChanged: (v) => setState(() => _paidThrough = v),
                    ),
            ]),
            _section('Depreciation Settings', [
              _dropdown<String>(
                label: 'Depreciation Method *',
                value: _depMethod,
                items: _depMethods
                    .map((m) => DropdownMenuItem(
                          value: m['value'],
                          child: Text(m['label']!),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _depMethod = v ?? _depMethod),
              ),
              if (_depMethod != 'none') ...[
                const SizedBox(height: 12),
                _dropdown<String>(
                  label: 'Depreciation Frequency',
                  value: _depFrequency,
                  items: _depFreqs
                      .map((f) => DropdownMenuItem(
                            value: f['value'],
                            child: Text(f['label']!),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _depFrequency = v ?? _depFrequency),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _field('Useful Life (months) *', _usefulLifeCtrl,
                        keyboardType: TextInputType.number,
                        validator: (v) => (int.tryParse(v ?? '') == null)
                            ? 'Enter months'
                            : null),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field('Salvage Value (₹)', _salvageCtrl,
                          keyboardType: TextInputType.number)),
                ]),
                if (_depMethod == 'declining_balance') ...[
                  const SizedBox(height: 12),
                  _field('Depreciation Rate (%)', _depRateCtrl,
                      keyboardType: TextInputType.number),
                ],
                const SizedBox(height: 12),
                _dateTile('Depreciation Start Date', _depStartDate,
                    onTap: () async {
                  final d = await _pickDate(_depStartDate);
                  if (d != null) setState(() => _depStartDate = d);
                }),
              ],
            ]),
            _section('COA Accounts', [
              _infoChip(
                  'These COA accounts will be auto-created if they don\'t exist.'),
              const SizedBox(height: 12),
              _field('Asset Account Name *', _assetAccCtrl,
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null),
              const SizedBox(height: 12),
              _field('Accumulated Depreciation Account', _depAccCtrl),
              const SizedBox(height: 12),
              _field('Depreciation Expense Account', _expAccCtrl),
            ]),
            _section('Notes', [
              _field('Notes (optional)', _notesCtrl, maxLines: 3),
            ]),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── Section wrapper ───────────────────────────────────────────────────────
  Widget _section(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E))),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  // ── Field helpers ─────────────────────────────────────────────────────────
  Widget _field(
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _dateTile(String label, String value, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Text(value, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _infoChip(String msg) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF1565C0)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF1565C0)))),
        ],
      ),
    );
  }
}
