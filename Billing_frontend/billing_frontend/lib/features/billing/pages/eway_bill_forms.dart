// ============================================================================
// E-WAY BILL — COMPLETE FLUTTER SCREENS
// ============================================================================
// File: lib/screens/billing/eway_bills/eway_bill_forms.dart
//
// CONTAINS:
//   1. EWayBillGenerateForm     — Part A + Part B form (pre-filled from invoice)
//   2. EWayBillDetailPage       — Detail view + Update Vehicle / Extend / Cancel / Print
//   3. ConsolidatedEWBForm      — Multi-EWB consolidation screen
//   4. AssociateEWBDialog       — Link manually generated EWB to source doc
//   5. EWBPendingBanner         — Smart notification widget (inline, not a page)
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/eway_bill_service.dart';

// ── shared palette ────────────────────────────────────────────────────────────
const Color _navy     = Color(0xFF1e3a8a);
const Color _navyDark = Color(0xFF0D1B3E);
const Color _green    = Color(0xFF27AE60);
const Color _blue     = Color(0xFF2980B9);
const Color _orange   = Color(0xFFE67E22);
const Color _red      = Color(0xFFE74C3C);
const Color _purple   = Color(0xFF9B59B6);

// ── Indian states list ────────────────────────────────────────────────────────
const List<Map<String, String>> _indianStates = [
  {'code': '01', 'name': 'Jammu & Kashmir'},   {'code': '02', 'name': 'Himachal Pradesh'},
  {'code': '03', 'name': 'Punjab'},            {'code': '04', 'name': 'Chandigarh'},
  {'code': '05', 'name': 'Uttarakhand'},       {'code': '06', 'name': 'Haryana'},
  {'code': '07', 'name': 'Delhi'},             {'code': '08', 'name': 'Rajasthan'},
  {'code': '09', 'name': 'Uttar Pradesh'},     {'code': '10', 'name': 'Bihar'},
  {'code': '11', 'name': 'Sikkim'},            {'code': '12', 'name': 'Arunachal Pradesh'},
  {'code': '13', 'name': 'Nagaland'},          {'code': '14', 'name': 'Manipur'},
  {'code': '15', 'name': 'Mizoram'},           {'code': '16', 'name': 'Tripura'},
  {'code': '17', 'name': 'Meghalaya'},         {'code': '18', 'name': 'Assam'},
  {'code': '19', 'name': 'West Bengal'},       {'code': '20', 'name': 'Jharkhand'},
  {'code': '21', 'name': 'Odisha'},            {'code': '22', 'name': 'Chhattisgarh'},
  {'code': '23', 'name': 'Madhya Pradesh'},    {'code': '24', 'name': 'Gujarat'},
  {'code': '27', 'name': 'Maharashtra'},       {'code': '29', 'name': 'Karnataka'},
  {'code': '30', 'name': 'Goa'},              {'code': '32', 'name': 'Kerala'},
  {'code': '33', 'name': 'Tamil Nadu'},        {'code': '36', 'name': 'Telangana'},
  {'code': '37', 'name': 'Andhra Pradesh'},
];

String _stateCode(String name) =>
    _indianStates.firstWhere((s) => s['name'] == name, orElse: () => {'code': ''})['code']!;

// =============================================================================
// 5. EWBPendingBanner — Smart notification banner widget
// =============================================================================
class EWBPendingBanner extends StatefulWidget {
  final VoidCallback? onTap;
  const EWBPendingBanner({Key? key, this.onTap}) : super(key: key);

  @override
  State<EWBPendingBanner> createState() => _EWBPendingBannerState();
}

class _EWBPendingBannerState extends State<EWBPendingBanner> {
  int  _count   = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await EWayBillService.getPendingCount();
      if (mounted) {
        setState(() {
          _count   = (res['data']?['pendingCount'] ?? 0) as int;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _count == 0) return const SizedBox.shrink();
    return InkWell(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _orange.withOpacity(0.4)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.notifications_active_outlined, color: _orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: RichText(text: TextSpan(
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            children: [
              TextSpan(
                text: '$_count invoice${_count > 1 ? 's' : ''} ',
                style: const TextStyle(fontWeight: FontWeight.bold, color: _orange),
              ),
              const TextSpan(text: 'require an e-Way Bill (total > ₹50,000)'),
            ],
          ))),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios, size: 14, color: _orange),
        ]),
      ),
    );
  }
}

// =============================================================================
// 4. AssociateEWBDialog
// =============================================================================
class AssociateEWBDialog extends StatefulWidget {
  final String? sourceType;
  final String? sourceId;
  final String? sourceNumber;

  const AssociateEWBDialog({Key? key, this.sourceType, this.sourceId, this.sourceNumber}) : super(key: key);

  @override
  State<AssociateEWBDialog> createState() => _AssociateEWBDialogState();
}

class _AssociateEWBDialogState extends State<AssociateEWBDialog> {
  final _ewbCtrl      = TextEditingController();
  final _ewbDateCtrl  = TextEditingController();
  final _validCtrl    = TextEditingController();
  DateTime? _ewbDate;
  DateTime? _validUntil;
  bool _saving = false;

  @override
  void dispose() {
    _ewbCtrl.dispose(); _ewbDateCtrl.dispose(); _validCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ewbNum = _ewbCtrl.text.trim();
    if (ewbNum.length != 12 || int.tryParse(ewbNum) == null) {
      _showError('EWB number must be exactly 12 digits');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await EWayBillService.associateEWB({
        'sourceType':   widget.sourceType   ?? 'INVOICE',
        'sourceId':     widget.sourceId     ?? '',
        'sourceNumber': widget.sourceNumber ?? '',
        'ewbNumber':    ewbNum,
        'ewbDate':      _ewbDate?.toIso8601String(),
        'validUntil':   _validUntil?.toIso8601String(),
      });
      setState(() => _saving = false);
      if (res['success'] == true) {
        Navigator.pop(context, true);
        _showSnack('EWB $ewbNum associated successfully', _green);
      } else {
        _showError(res['message'] ?? 'Association failed');
      }
    } catch (e) {
      setState(() => _saving = false);
      _showError(e.toString());
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  void _showSnack(String msg, Color c) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: c, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_navyDark, _navy]),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Associate e-Way Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Link a manually generated EWB number to ${widget.sourceNumber ?? 'this document'}',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
        ]),
      ),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        // Info note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _blue.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _blue.withOpacity(0.2))),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: _blue, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'If you generated the EWB directly on ewaybillgst.gov.in, enter the 12-digit EWB number here to link it to this document.',
              style: TextStyle(fontSize: 12, color: _blue),
            )),
          ]),
        ),
        const SizedBox(height: 16),
        // EWB Number field
        TextField(
          controller: _ewbCtrl,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _inputDec('12-digit EWB Number *', '123456789012', icon: Icons.receipt_long),
        ),
        const SizedBox(height: 12),
        // EWB Date
        InkWell(
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now(),
              firstDate: DateTime(2020), lastDate: DateTime.now(),
              builder: (c, ch) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: ch!));
            if (d != null) setState(() { _ewbDate = d; _ewbDateCtrl.text = DateFormat('dd MMM yyyy').format(d); });
          },
          child: InputDecorator(
            decoration: _inputDec('EWB Generation Date', 'Optional'),
            child: Text(_ewbDate != null ? DateFormat('dd MMM yyyy').format(_ewbDate!) : 'Select date',
                style: TextStyle(color: _ewbDate != null ? Colors.black87 : Colors.grey[400], fontSize: 14)),
          ),
        ),
        const SizedBox(height: 12),
        // Valid Until
        InkWell(
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 3)),
              firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)),
              builder: (c, ch) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: ch!));
            if (d != null) setState(() { _validUntil = d; _validCtrl.text = DateFormat('dd MMM yyyy').format(d); });
          },
          child: InputDecorator(
            decoration: _inputDec('Valid Until', 'Optional'),
            child: Text(_validUntil != null ? DateFormat('dd MMM yyyy').format(_validUntil!) : 'Select date',
                style: TextStyle(color: _validUntil != null ? Colors.black87 : Colors.grey[400], fontSize: 14)),
          ),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Associate EWB'),
        ),
      ],
    );
  }

  InputDecoration _inputDec(String label, String hint, {IconData? icon}) => InputDecoration(
    labelText: label, hintText: hint,
    prefixIcon: icon != null ? Icon(icon, size: 18, color: Colors.grey[400]) : null,
    labelStyle: const TextStyle(fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    filled: true, fillColor: const Color(0xFFF7F9FC),
    counterText: '',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)),
  );
}

// =============================================================================
// 3. ConsolidatedEWBForm
// =============================================================================
class ConsolidatedEWBForm extends StatefulWidget {
  const ConsolidatedEWBForm({Key? key}) : super(key: key);
  @override
  State<ConsolidatedEWBForm> createState() => _ConsolidatedEWBFormState();
}

class _ConsolidatedEWBFormState extends State<ConsolidatedEWBForm> {
  final _vehicleCtrl    = TextEditingController();
  final _fromPlaceCtrl  = TextEditingController();
  String _transportMode = 'ROAD';
  String _fromState     = '';
  String _vehicleType   = 'REGULAR';
  bool   _saving        = false;

  // EWB entries list — each entry has controller + model
  final List<TextEditingController> _ewbCtrls = [
    TextEditingController(), TextEditingController(),
  ];
  List<EWayBillModel?> _selectedEWBs = [null, null];

  // Loaded EWBs for picker
  List<EWayBillModel> _availableEWBs = [];
  bool _loadingEWBs = true;

  @override
  void initState() { super.initState(); _loadAvailableEWBs(); }

  Future<void> _loadAvailableEWBs() async {
    try {
      final res = await EWayBillService.getEWayBills(status: 'GENERATED', limit: 100);
      final list = (res['data'] as List? ?? [])
          .map((e) => EWayBillModel.fromJson(e))
          .where((e) => e.ewbNumber != null && !e.isConsolidated)
          .toList();
      setState(() { _availableEWBs = list; _loadingEWBs = false; });
    } catch (_) {
      setState(() => _loadingEWBs = false);
    }
  }

  void _addRow() {
    setState(() {
      _ewbCtrls.add(TextEditingController());
      _selectedEWBs.add(null);
    });
  }

  void _removeRow(int i) {
    if (_ewbCtrls.length <= 2) return;
    setState(() {
      _ewbCtrls[i].dispose();
      _ewbCtrls.removeAt(i);
      _selectedEWBs.removeAt(i);
    });
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose(); _fromPlaceCtrl.dispose();
    for (final c in _ewbCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_vehicleCtrl.text.trim().isEmpty) { _showError('Vehicle number is required'); return; }
    final ewbNumbers = _ewbCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (ewbNumbers.length < 2) { _showError('At least 2 EWB numbers are required'); return; }

    setState(() => _saving = true);
    try {
      final res = await EWayBillService.generateConsolidatedEWB({
        'vehicleNumber':  _vehicleCtrl.text.trim().toUpperCase(),
        'fromPlace':      _fromPlaceCtrl.text.trim(),
        'fromState':      _fromState,
        'transportMode':  _transportMode,
        'vehicleType':    _vehicleType,
        'ewbNumbers':     ewbNumbers,
      });
      setState(() => _saving = false);
      if (res['success'] == true) {
        final cewbNo = res['data']?['cewbNumber'] ?? '';
        _showSuccess('Consolidated EWB $cewbNo generated successfully!');
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context, true);
      } else {
        _showError(res['message'] ?? 'Generation failed');
      }
    } catch (e) {
      setState(() => _saving = false);
      _showError(e.toString());
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 16), const SizedBox(width: 8), Expanded(child: Text(msg))]),
    backgroundColor: _red, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 4)));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 16), const SizedBox(width: 8), Expanded(child: Text(msg))]),
    backgroundColor: _green, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [_navyDark, _navy], begin: Alignment.centerLeft, end: Alignment.centerRight)),
          child: AppBar(
            backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white,
            title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Consolidated e-Way Bill', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Text('One vehicle — multiple consignments', style: TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
            actions: [
              ElevatedButton.icon(
                onPressed: _saving ? null : _generate,
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.merge_type, size: 18),
                label: Text(_saving ? 'Generating…' : 'Generate CEWB'),
                style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(builder: (_, c) {
          final isWide = c.maxWidth > 800;
          if (isWide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: Column(children: [_buildVehicleSection(), const SizedBox(height: 16), _buildEWBListSection()])),
              const SizedBox(width: 16),
              SizedBox(width: 280, child: _buildInfoPanel()),
            ]);
          }
          return Column(children: [_buildVehicleSection(), const SizedBox(height: 16), _buildEWBListSection(), const SizedBox(height: 16), _buildInfoPanel()]);
        }),
      ),
    );
  }

  Widget _buildVehicleSection() => _card(
    title: 'Vehicle Details', icon: Icons.local_shipping_outlined,
    child: Column(children: [
      Row(children: [
        Expanded(child: _field('Vehicle Number *', _vehicleCtrl, hint: 'e.g. KA01AB1234',
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))])),
        const SizedBox(width: 12),
        Expanded(child: _dropdown('Vehicle Type', _vehicleType, ['REGULAR', 'OVER_DIMENSIONAL_CARGO'],
          (v) => setState(() => _vehicleType = v!),
          labels: {'REGULAR': 'Regular', 'OVER_DIMENSIONAL_CARGO': 'Over Dimensional Cargo'})),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _dropdown('Transport Mode', _transportMode, ['ROAD', 'RAIL', 'AIR', 'SHIP'],
          (v) => setState(() => _transportMode = v!))),
        const SizedBox(width: 12),
        Expanded(child: _field('From Place', _fromPlaceCtrl, hint: 'Starting location')),
        const SizedBox(width: 12),
        Expanded(child: _stateDropdown('From State', _fromState, (v) => setState(() => _fromState = v))),
      ]),
    ]),
  );

  Widget _buildEWBListSection() => _card(
    title: 'e-Way Bills to Consolidate', icon: Icons.receipt_long_outlined,
    child: Column(children: [
      Container(
        padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: _blue.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _blue.withOpacity(0.2))),
        child: const Row(children: [
          Icon(Icons.info_outline, color: _blue, size: 14),
          SizedBox(width: 8),
          Expanded(child: Text('Minimum 2 EWBs required. All EWBs must be in GENERATED status and not already consolidated.',
            style: TextStyle(fontSize: 12, color: _blue))),
        ]),
      ),
      // EWB rows
      ...List.generate(_ewbCtrls.length, (i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
            child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)))),
          const SizedBox(width: 10),
          // Dropdown from available EWBs
          Expanded(child: _loadingEWBs
            ? const LinearProgressIndicator()
            : _availableEWBs.isEmpty
              ? TextField(
                  controller: _ewbCtrls[i],
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec('EWB Number *', hint: '12-digit EWB number').copyWith(counterText: ''),
                )
              : DropdownButtonFormField<String>(
                  value: _ewbCtrls[i].text.isNotEmpty ? _ewbCtrls[i].text : null,
                  decoration: _dec('Select EWB *'),
                  hint: const Text('Select e-Way Bill', style: TextStyle(fontSize: 13)),
                  items: _availableEWBs.map((e) => DropdownMenuItem(
                    value: e.ewbNumber,
                    child: Text('${e.ewbNumber} — ${e.toTradeName} (${e.sourceNumber})',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() {
                      _ewbCtrls[i].text = v;
                      _selectedEWBs[i]  = _availableEWBs.firstWhere((e) => e.ewbNumber == v);
                    });
                  },
                )),
          const SizedBox(width: 8),
          if (i >= 2)
            IconButton(
              onPressed: () => _removeRow(i),
              icon: const Icon(Icons.remove_circle_outline, color: _red, size: 20),
              tooltip: 'Remove',
            )
          else
            const SizedBox(width: 40),
        ]),
      )),
      // Add row button
      TextButton.icon(
        onPressed: _addRow,
        icon: const Icon(Icons.add_circle_outline, size: 18, color: _navy),
        label: const Text('Add another EWB', style: TextStyle(color: _navy, fontWeight: FontWeight.w600)),
      ),
    ]),
  );

  Widget _buildInfoPanel() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('About Consolidated EWB', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navyDark)),
      const SizedBox(height: 12),
      _infoItem(Icons.local_shipping_outlined, 'One vehicle carrying multiple consignments'),
      _infoItem(Icons.receipt_long_outlined,   'Covers all individual EWBs in one document'),
      _infoItem(Icons.check_circle_outline,    'Each individual EWB must be in GENERATED status'),
      _infoItem(Icons.person_outline,          'Can be created by consignor or transporter'),
      const Divider(height: 20),
      const Text('EWBs to consolidate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navyDark)),
      const SizedBox(height: 8),
      ...List.generate(_ewbCtrls.length, (i) {
        final num = _ewbCtrls[i].text;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(width: 20, height: 20, decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)))),
            const SizedBox(width: 8),
            Expanded(child: Text(num.isNotEmpty ? num : '—', style: TextStyle(fontSize: 12, color: num.isNotEmpty ? _navyDark : Colors.grey[400]))),
          ]),
        );
      }),
    ]),
  );

  Widget _infoItem(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 15, color: _blue),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87))),
    ]));

  Widget _card({required String title, required IconData icon, required Widget child}) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(color: _navyDark.withOpacity(0.04),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(gradient: const LinearGradient(colors: [_navyDark, _navy]), borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        ])),
      Padding(padding: const EdgeInsets.all(20), child: child),
    ]));

  Widget _field(String label, TextEditingController ctrl, {String? hint, List<TextInputFormatter>? inputFormatters}) =>
    TextFormField(controller: ctrl, inputFormatters: inputFormatters, decoration: _dec(label, hint: hint));

  Widget _dropdown(String label, String value, List<String> opts, ValueChanged<String?> onChanged, {Map<String, String>? labels}) =>
    DropdownButtonFormField<String>(
      value: value, decoration: _dec(label),
      items: opts.map((o) => DropdownMenuItem(value: o, child: Text(labels?[o] ?? o.replaceAll('_', ' '), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );

  Widget _stateDropdown(String label, String value, ValueChanged<String> onChanged) =>
    DropdownButtonFormField<String>(
      value: value.isNotEmpty ? value : null,
      decoration: _dec(label),
      hint: const Text('Select state', overflow: TextOverflow.ellipsis),
      items: _indianStates.map((s) => DropdownMenuItem(value: s['name'], child: Text(s['name']!, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
    labelText: label, hintText: hint, labelStyle: const TextStyle(fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    filled: true, fillColor: const Color(0xFFF7F9FC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)),
  );
}

// =============================================================================
// 1. EWayBillGenerateForm
// =============================================================================
class EWayBillGenerateForm extends StatefulWidget {
  final String? sourceType;
  final String? sourceId;
  final String? sourceNumber;
  final Map<String, dynamic>? prefillData;

  const EWayBillGenerateForm({Key? key, this.sourceType, this.sourceId, this.sourceNumber, this.prefillData}) : super(key: key);

  @override
  State<EWayBillGenerateForm> createState() => _EWayBillGenerateFormState();
}

class _EWayBillGenerateFormState extends State<EWayBillGenerateForm> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving  = false;
  bool _partBSkip = false;

  // Part A
  String _sourceType   = 'INVOICE';
  String _supplyType   = 'OUTWARD';
  String _subType      = 'SUPPLY';
  String _documentType = 'INV';
  DateTime _docDate    = DateTime.now();

  final _sourceIdCtrl    = TextEditingController();
  final _sourceNumCtrl   = TextEditingController();
  final _docNumberCtrl   = TextEditingController();
  final _fromGstinCtrl   = TextEditingController();
  final _fromNameCtrl    = TextEditingController();
  final _fromAddr1Ctrl   = TextEditingController();
  final _fromPlaceCtrl   = TextEditingController();
  final _fromPincodeCtrl = TextEditingController();
  String _fromState      = '';
  String _fromStateCode  = '';
  final _toGstinCtrl     = TextEditingController();
  final _toNameCtrl      = TextEditingController();
  final _toAddr1Ctrl     = TextEditingController();
  final _toPlaceCtrl     = TextEditingController();
  final _toPincodeCtrl   = TextEditingController();
  String _toState        = '';
  String _toStateCode    = '';
  final _hsnCtrl         = TextEditingController();
  final _productCtrl     = TextEditingController();
  final _quantityCtrl    = TextEditingController(text: '1');
  String _unit           = 'NOS';
  final _taxableCtrl     = TextEditingController();
  final _cgstCtrl        = TextEditingController(text: '9');
  final _sgstCtrl        = TextEditingController(text: '9');
  final _igstCtrl        = TextEditingController(text: '0');
  final _totalValueCtrl  = TextEditingController();

  // Transport
  String _transportMode        = 'ROAD';
  final _distanceCtrl          = TextEditingController();
  final _transporterNameCtrl   = TextEditingController();
  final _transporterIdCtrl     = TextEditingController();
  final _transDocNoCtrl        = TextEditingController();
  DateTime? _transDocDate;

  // Part B
  String _vehicleType        = 'REGULAR';
  final _vehicleNumCtrl      = TextEditingController();
  final _partBFromPlaceCtrl  = TextEditingController();
  String _partBFromState     = '';
  String _reasonCode         = '1';

  @override
  void initState() {
    super.initState();
    if (widget.sourceType   != null) _sourceType = widget.sourceType!;
    if (widget.sourceId     != null) _sourceIdCtrl.text  = widget.sourceId!;
    if (widget.sourceNumber != null) { _sourceNumCtrl.text = widget.sourceNumber!; _docNumberCtrl.text = widget.sourceNumber!; }
    if (widget.prefillData  != null) _prefill(widget.prefillData!);
    _distanceCtrl.addListener(_checkDistance);
  }

  void _prefill(Map<String, dynamic> d) {
    _fromGstinCtrl.text   = d['fromGstin']     ?? '';
    _fromNameCtrl.text    = d['fromTradeName']  ?? '';
    _fromAddr1Ctrl.text   = d['fromAddress']    ?? '';
    _fromPlaceCtrl.text   = d['fromCity']       ?? '';
    _fromPincodeCtrl.text = d['fromPincode']    ?? '';
    _fromState            = d['fromState']      ?? '';
    _fromStateCode        = d['fromStateCode']  ?? '';
    _toGstinCtrl.text     = d['customerGSTIN']  ?? '';
    _toNameCtrl.text      = d['customerName']   ?? '';
    _toAddr1Ctrl.text     = d['billingAddress'] ?? '';
    _toPlaceCtrl.text     = d['billingCity']    ?? '';
    _toPincodeCtrl.text   = d['billingPincode'] ?? '';
    _toState              = d['placeOfSupply']  ?? '';
    _toStateCode          = d['toStateCode']    ?? '';
    _hsnCtrl.text         = d['hsnCode']        ?? '';
    _productCtrl.text     = d['itemName']       ?? '';
    _taxableCtrl.text     = d['taxableAmount']?.toString()  ?? '';
    _totalValueCtrl.text  = d['totalAmount']?.toString()    ?? '';
    if (d['invoiceDate'] != null) _docDate = DateTime.tryParse(d['invoiceDate']) ?? DateTime.now();
    _docNumberCtrl.text   = d['invoiceNumber']  ?? _docNumberCtrl.text;
  }

  void _checkDistance() {
    final dist = int.tryParse(_distanceCtrl.text) ?? 0;
    setState(() => _partBSkip = dist > 0 && dist <= 50);
  }

  @override
  void dispose() {
    _distanceCtrl.removeListener(_checkDistance);
    for (final c in [_sourceIdCtrl, _sourceNumCtrl, _docNumberCtrl, _fromGstinCtrl, _fromNameCtrl,
        _fromAddr1Ctrl, _fromPlaceCtrl, _fromPincodeCtrl, _toGstinCtrl, _toNameCtrl, _toAddr1Ctrl,
        _toPlaceCtrl, _toPincodeCtrl, _hsnCtrl, _productCtrl, _quantityCtrl, _taxableCtrl, _cgstCtrl,
        _sgstCtrl, _igstCtrl, _totalValueCtrl, _distanceCtrl, _transporterNameCtrl, _transporterIdCtrl,
        _transDocNoCtrl, _vehicleNumCtrl, _partBFromPlaceCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_distanceCtrl.text.isEmpty || int.tryParse(_distanceCtrl.text) == null) {
      _showError('Approximate distance is required'); return;
    }
    setState(() => _isSaving = true);
    try {
      final data = {
        'sourceType': _sourceType, 'sourceId': _sourceIdCtrl.text.trim(),
        'sourceNumber': _sourceNumCtrl.text.trim(), 'supplyType': _supplyType,
        'subType': _subType, 'documentType': _documentType,
        'documentNumber': _docNumberCtrl.text.trim(), 'documentDate': _docDate.toIso8601String(),
        'fromGstin': _fromGstinCtrl.text.trim(), 'fromTradeName': _fromNameCtrl.text.trim(),
        'fromAddress1': _fromAddr1Ctrl.text.trim(), 'fromPlace': _fromPlaceCtrl.text.trim(),
        'fromPincode': _fromPincodeCtrl.text.trim(), 'fromStateCode': _fromStateCode, 'fromState': _fromState,
        'toGstin': _toGstinCtrl.text.trim(), 'toTradeName': _toNameCtrl.text.trim(),
        'toAddress1': _toAddr1Ctrl.text.trim(), 'toPlace': _toPlaceCtrl.text.trim(),
        'toPincode': _toPincodeCtrl.text.trim(), 'toStateCode': _toStateCode, 'toState': _toState,
        'hsnCode': _hsnCtrl.text.trim(), 'productName': _productCtrl.text.trim(),
        'quantity': double.tryParse(_quantityCtrl.text) ?? 1,
        'unit': _unit,
        'taxableAmount': double.tryParse(_taxableCtrl.text) ?? 0,
        'cgstRate': double.tryParse(_cgstCtrl.text) ?? 0,
        'sgstRate': double.tryParse(_sgstCtrl.text) ?? 0,
        'igstRate': double.tryParse(_igstCtrl.text) ?? 0,
        'totalInvoiceValue': double.tryParse(_totalValueCtrl.text) ?? 0,
        'transportMode': _transportMode,
        'approximateDistance': int.tryParse(_distanceCtrl.text) ?? 0,
        'transporterName': _transporterNameCtrl.text.trim(),
        'transporterId': _transporterIdCtrl.text.trim(),
        'transDocNo': _transDocNoCtrl.text.trim(),
        'transDocDate': _transDocDate?.toIso8601String(),
        if (!_partBSkip && _vehicleNumCtrl.text.trim().isNotEmpty) ...{
          'vehicleType': _vehicleType, 'vehicleNumber': _vehicleNumCtrl.text.trim(),
          'fromPlacePartB': _partBFromPlaceCtrl.text.trim(), 'fromStatePartB': _partBFromState, 'reasonCode': _reasonCode,
        },
      };
      final res = await EWayBillService.generateEWayBill(data);
      setState(() => _isSaving = false);
      if (res['success'] == true) {
        final ewbNumber = (res['data'] as Map?)?['ewbNumber'] ?? '';
        _showSuccess('e-Way Bill $ewbNumber generated successfully!');
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context, true);
      } else {
        _showError(res['message'] ?? 'Failed to generate EWB');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showError(e.toString());
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
    backgroundColor: _red, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 4)));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
    backgroundColor: _green, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  String _getValidity() {
    final d = int.tryParse(_distanceCtrl.text) ?? 0;
    if (d <= 0)    return '—';
    if (d <= 100)  return '1 day';
    if (d <= 300)  return '3 days';
    if (d <= 500)  return '5 days';
    if (d <= 1000) return '10 days';
    return '15 days';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [_navyDark, _navy], begin: Alignment.centerLeft, end: Alignment.centerRight)),
          child: AppBar(
            backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white,
            title: const Text('Generate e-Way Bill', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            actions: [
              TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white70, size: 18), label: const Text('Cancel', style: TextStyle(color: Colors.white70))),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 18),
                label: Text(_isSaving ? 'Generating…' : 'Generate EWB'),
                style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(builder: (_, c) {
          final isWide = c.maxWidth > 800;
          final main = SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              _buildSourceCard(),   const SizedBox(height: 16),
              _buildPartACard(),    const SizedBox(height: 16),
              _buildTransportCard(),const SizedBox(height: 16),
              if (!_partBSkip) _buildPartBCard(),
              if (_partBSkip)  _buildPartBSkipNotice(),
              const SizedBox(height: 20),
            ]),
          );
          if (isWide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: main),
              Container(width: 290, color: Colors.white,
                child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _buildSummaryPanel())),
            ]);
          }
          return main;
        }),
      ),
    );
  }

  Widget _buildSourceCard() => _formCard('Source Document', Icons.description_outlined, Column(children: [
    Row(children: [
      Expanded(child: _dd('Source Type', _sourceType, ['INVOICE','CREDIT_NOTE','DELIVERY_CHALLAN','BILL_OF_SUPPLY'],
        (v) => setState(() { _sourceType = v!; _documentType = v == 'INVOICE' ? 'INV' : v == 'CREDIT_NOTE' ? 'CREDIT_NOTE' : 'DELIVERY_CHALLAN'; }))),
      const SizedBox(width: 12),
      Expanded(child: _tf('Document Number *', _docNumberCtrl, required: true)),
    ]),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: _dd('Supply Type', _supplyType, ['OUTWARD','INWARD'], (v) => setState(() => _supplyType = v!))),
      const SizedBox(width: 12),
      Expanded(child: _dd('Sub Type', _subType,
        ['SUPPLY','EXPORT','JOB_WORK','SKD_CKD','FOR_OWN_USE','EXHIBITION_FAIRS','OTHERS'],
        (v) => setState(() => _subType = v!))),
    ]),
  ]));

  Widget _buildPartACard() => _formCard('Part A — Consignor & Consignee', Icons.swap_horiz_rounded, Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    _subLabel('FROM (Consignor / Seller)'), const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _tf('GSTIN *', _fromGstinCtrl, required: true, maxLen: 15)),
      const SizedBox(width: 12),
      Expanded(child: _tf('Trade Name *', _fromNameCtrl, required: true)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(flex: 2, child: _tf('Address', _fromAddr1Ctrl)),
      const SizedBox(width: 12),
      Expanded(child: _tf('City *', _fromPlaceCtrl, required: true)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _tf('Pincode *', _fromPincodeCtrl, required: true, inputType: TextInputType.number, maxLen: 6)),
      const SizedBox(width: 12),
      Expanded(child: _stateDd('State *', _fromState, (v, code) => setState(() { _fromState = v; _fromStateCode = code; }))),
    ]),
    const Divider(height: 24),
    _subLabel('TO (Consignee / Buyer)'), const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _tf('GSTIN', _toGstinCtrl, maxLen: 15)),
      const SizedBox(width: 12),
      Expanded(child: _tf('Trade Name *', _toNameCtrl, required: true)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(flex: 2, child: _tf('Address', _toAddr1Ctrl)),
      const SizedBox(width: 12),
      Expanded(child: _tf('City *', _toPlaceCtrl, required: true)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _tf('Pincode *', _toPincodeCtrl, required: true, inputType: TextInputType.number, maxLen: 6)),
      const SizedBox(width: 12),
      Expanded(child: _stateDd('State *', _toState, (v, code) => setState(() { _toState = v; _toStateCode = code; }))),
    ]),
    const Divider(height: 24),
    _subLabel('Goods Details'), const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _tf('HSN Code *', _hsnCtrl, required: true)),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: _tf('Product Name *', _productCtrl, required: true)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _tf('Qty *', _quantityCtrl, required: true, inputType: TextInputType.number)),
      const SizedBox(width: 12),
      Expanded(child: _dd('Unit', _unit, ['NOS','KGS','MTR','LTR','BOX','PCS','SQF','SQM','OTH'], (v) => setState(() => _unit = v!))),
      const SizedBox(width: 12),
      Expanded(child: _tf('Taxable Value (₹) *', _taxableCtrl, required: true, inputType: TextInputType.number)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _tf('CGST %', _cgstCtrl, inputType: TextInputType.number)),
      const SizedBox(width: 12),
      Expanded(child: _tf('SGST %', _sgstCtrl, inputType: TextInputType.number)),
      const SizedBox(width: 12),
      Expanded(child: _tf('IGST %', _igstCtrl, inputType: TextInputType.number)),
      const SizedBox(width: 12),
      Expanded(child: _tf('Total Value (₹) *', _totalValueCtrl, required: true, inputType: TextInputType.number)),
    ]),
  ]));

  Widget _buildTransportCard() => _formCard('Transport Details', Icons.local_shipping_outlined, Column(children: [
    Row(children: [
      Expanded(child: _dd('Mode *', _transportMode, ['ROAD','RAIL','AIR','SHIP'], (v) => setState(() => _transportMode = v!))),
      const SizedBox(width: 12),
      Expanded(child: _tf('Approx. Distance (km) *', _distanceCtrl, required: true,
        inputType: TextInputType.number, helper: '≤50km: Part B optional')),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _tf('Transporter Name', _transporterNameCtrl)),
      const SizedBox(width: 12),
      Expanded(child: _tf('Transporter ID', _transporterIdCtrl, maxLen: 15)),
    ]),
  ]));

  Widget _buildPartBCard() => _formCard('Part B — Vehicle Details', Icons.directions_car_outlined, Column(children: [
    Container(padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: _blue.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _blue.withOpacity(0.2))),
      child: const Row(children: [Icon(Icons.info_outline, color: _blue, size: 14), SizedBox(width: 8),
        Expanded(child: Text('Part B required for distances > 50km. If transporter will fill, vehicle number is optional.', style: TextStyle(fontSize: 12, color: _blue)))])),
    Row(children: [
      Expanded(child: _tf('Vehicle Number', _vehicleNumCtrl, hint: 'e.g. KA01AB1234')),
      const SizedBox(width: 12),
      Expanded(child: _dd('Vehicle Type', _vehicleType, ['REGULAR','OVER_DIMENSIONAL_CARGO'],
        (v) => setState(() => _vehicleType = v!),
        labels: {'REGULAR': 'Regular', 'OVER_DIMENSIONAL_CARGO': 'Over Dimensional'})),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _tf('From Place', _partBFromPlaceCtrl, hint: 'Starting location')),
      const SizedBox(width: 12),
      Expanded(child: _stateDd('From State', _partBFromState, (v, _) => setState(() => _partBFromState = v))),
      const SizedBox(width: 12),
      Expanded(child: _dd('Reason', _reasonCode, ['1','2','3','4'], (v) => setState(() => _reasonCode = v!),
        labels: {'1': 'First Time', '2': 'Breakdown', '3': 'Transshipment', '4': 'Others'})),
    ]),
  ]));

  Widget _buildPartBSkipNotice() => Container(
    padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: _green.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _green.withOpacity(0.3))),
    child: const Row(children: [Icon(Icons.check_circle_outline, color: _green, size: 20), SizedBox(width: 10),
      Expanded(child: Text('Distance ≤ 50km — Part B not required for this e-Way Bill.', style: TextStyle(fontSize: 13, color: _green, fontWeight: FontWeight.w500)))]));

  Widget _buildSummaryPanel() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('EWB Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
    const SizedBox(height: 4),
    Text('Review before generating', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    const SizedBox(height: 16),
    _sumRow('Document',  _docNumberCtrl.text.isNotEmpty ? _docNumberCtrl.text : '—'),
    _sumRow('From',      _fromNameCtrl.text.isNotEmpty  ? _fromNameCtrl.text  : '—'),
    _sumRow('To',        _toNameCtrl.text.isNotEmpty    ? _toNameCtrl.text    : '—'),
    _sumRow('Mode',      _transportMode),
    _sumRow('Distance',  _distanceCtrl.text.isNotEmpty  ? '${_distanceCtrl.text} km' : '—'),
    if (_distanceCtrl.text.isNotEmpty) ...[const Divider(height: 20), _sumRow('Est. Validity', _getValidity())],
    const Divider(height: 20),
    _sumRow('Taxable',   _taxableCtrl.text.isNotEmpty   ? '₹${_taxableCtrl.text}'    : '—'),
    _sumRow('Total',     _totalValueCtrl.text.isNotEmpty ? '₹${_totalValueCtrl.text}' : '—'),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, height: 46,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _submit,
        style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Generate e-Way Bill', style: TextStyle(fontWeight: FontWeight.w600)))),
  ]);

  Widget _sumRow(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      Flexible(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navyDark), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
    ]));

  Widget _subLabel(String t) => Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy));

  Widget _formCard(String title, IconData icon, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(color: _navyDark.withOpacity(0.04),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(gradient: const LinearGradient(colors: [_navyDark, _navy]), borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        ])),
      Padding(padding: const EdgeInsets.all(20), child: child),
    ]));

  Widget _tf(String label, TextEditingController ctrl, {bool required = false, String? hint, TextInputType? inputType, int? maxLen, String? helper}) =>
    TextFormField(controller: ctrl, keyboardType: inputType, maxLength: maxLen,
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
      decoration: _dec(label, hint: hint, helper: helper).copyWith(counterText: ''));

  Widget _dd(String label, String value, List<String> opts, ValueChanged<String?> onChanged, {Map<String, String>? labels}) =>
    DropdownButtonFormField<String>(
      value: value, decoration: _dec(label),
      items: opts.map((o) => DropdownMenuItem(value: o, child: Text(labels?[o] ?? o.replaceAll('_', ' '), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged);

  Widget _stateDd(String label, String value, Function(String, String) onChanged) =>
    DropdownButtonFormField<String>(
      value: value.isNotEmpty ? value : null, decoration: _dec(label),
      hint: const Text('Select state', overflow: TextOverflow.ellipsis),
      items: _indianStates.map((s) => DropdownMenuItem(value: s['name'], child: Text(s['name']!, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) { if (v != null) { final code = _stateCode(v); onChanged(v, code); } });

  InputDecoration _dec(String label, {String? hint, String? helper}) => InputDecoration(
    labelText: label, hintText: hint, helperText: helper, labelStyle: const TextStyle(fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    filled: true, fillColor: const Color(0xFFF7F9FC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _red)));
}

// =============================================================================
// 2. EWayBillDetailPage
// =============================================================================
class EWayBillDetailPage extends StatefulWidget {
  final String ewbId;
  const EWayBillDetailPage({Key? key, required this.ewbId}) : super(key: key);

  @override
  State<EWayBillDetailPage> createState() => _EWayBillDetailPageState();
}

class _EWayBillDetailPageState extends State<EWayBillDetailPage> {
  EWayBillModel? _ewb;
  bool _loading    = true;
  bool _printing   = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await EWayBillService.getEWayBillById(widget.ewbId);
      setState(() { _ewb = EWayBillModel.fromJson(res['data']); _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  // ── Print / Download PDF ───────────────────────────────────────────────────
  Future<void> _printPDF() async {
    setState(() => _printing = true);
    try {
      final res = await EWayBillService.downloadEWBPdf(widget.ewbId);
      setState(() => _printing = false);
      if (res['success'] == true) {
        _snack('PDF download started', _green);
      } else {
        _snack(res['message'] ?? 'PDF generation failed', _red);
      }
    } catch (e) {
      setState(() => _printing = false);
      _snack(e.toString(), _red);
    }
  }

  // ── Update Vehicle ─────────────────────────────────────────────────────────
  Future<void> _showUpdateVehicle() async {
    final vehicleCtrl = TextEditingController();
    final placeCtrl   = TextEditingController();
    String state      = '';
    String reason     = '1';

    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Update Vehicle Details', style: TextStyle(fontWeight: FontWeight.bold, color: _navyDark)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: vehicleCtrl, textCapitalization: TextCapitalization.characters,
          decoration: _inputDec('Vehicle Number *', 'e.g. KA01AB1234')),
        const SizedBox(height: 12),
        TextField(controller: placeCtrl, decoration: _inputDec('From Place', 'Current location')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: reason, decoration: _inputDec('Reason', ''),
          items: const [
            DropdownMenuItem(value: '1', child: Text('First Time')),
            DropdownMenuItem(value: '2', child: Text('Vehicle Breakdown')),
            DropdownMenuItem(value: '3', child: Text('Transshipment')),
            DropdownMenuItem(value: '4', child: Text('Others')),
          ],
          onChanged: (v) => ss(() => reason = v!)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
          child: const Text('Update')),
      ],
    )));

    if (ok != true || vehicleCtrl.text.trim().isEmpty) return;
    try {
      final res = await EWayBillService.updatePartB(widget.ewbId, {
        'vehicleNumber': vehicleCtrl.text.trim(), 'fromPlace': placeCtrl.text.trim(),
        'fromState': state, 'reasonCode': reason,
      });
      if (res['success'] == true) { _snack('Vehicle details updated', _green); _load(); }
      else { _snack(res['message'] ?? 'Update failed', _red); }
    } catch (e) { _snack(e.toString(), _red); }
  }

  // ── Extend Validity ────────────────────────────────────────────────────────
  Future<void> _showExtend() async {
    final distCtrl    = TextEditingController();
    final vehicleCtrl = TextEditingController(text: _ewb?.vehicleNumber ?? '');
    String reason     = 'Natural calamity / disaster';

    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Extend EWB Validity', style: TextStyle(fontWeight: FontWeight.bold, color: _navyDark)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: _orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _orange.withOpacity(0.3))),
          child: const Text('Extension available within 4 hours before or after EWB expiry.', style: TextStyle(fontSize: 12, color: _orange))),
        TextField(controller: distCtrl, keyboardType: TextInputType.number, decoration: _inputDec('Remaining Distance (km) *', 'e.g. 150')),
        const SizedBox(height: 12),
        TextField(controller: vehicleCtrl, decoration: _inputDec('Vehicle Number', 'Optional')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: reason, decoration: _inputDec('Reason', ''),
          items: ['Natural calamity / disaster', 'Law and order situation', 'Transhipment', 'Accident', 'Others']
            .map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => ss(() => reason = v!)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
          child: const Text('Extend Validity')),
      ],
    )));

    if (ok != true) return;
    try {
      final res = await EWayBillService.extendValidity(widget.ewbId, {
        'remainingDistance': int.tryParse(distCtrl.text) ?? 100,
        'vehicleNumber': vehicleCtrl.text.trim(), 'reason': reason,
      });
      if (res['success'] == true) { _snack('Validity extended', _green); _load(); }
      else { _snack(res['message'] ?? 'Extension failed', _red); }
    } catch (e) { _snack(e.toString(), _red); }
  }

  // ── Cancel EWB ─────────────────────────────────────────────────────────────
  Future<void> _showCancel() async {
    String reason = 'Duplicate';
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Cancel e-Way Bill', style: TextStyle(fontWeight: FontWeight.bold, color: _red)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: _red.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _red.withOpacity(0.3))),
          child: const Text('⚠️ IRREVERSIBLE. EWB can only be cancelled within 24 hours of generation.', style: TextStyle(fontSize: 12, color: _red))),
        DropdownButtonFormField<String>(
          value: reason, decoration: _inputDec('Cancel Reason *', ''),
          items: ['Duplicate', 'Order Cancelled', 'Data Entry Mistake', 'Others']
            .map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => ss(() => reason = v!)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep EWB')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
          child: const Text('Cancel EWB')),
      ],
    )));

    if (ok != true) return;
    try {
      final res = await EWayBillService.cancelEWayBill(widget.ewbId, reason);
      if (res['success'] == true) { _snack('EWB cancelled', _green); _load(); Navigator.pop(context, true); }
      else { _snack(res['message'] ?? 'Cancel failed', _red); }
    } catch (e) { _snack(e.toString(), _red); }
  }

  // ── Associate EWB ──────────────────────────────────────────────────────────
  Future<void> _showAssociate() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AssociateEWBDialog(
      sourceType:   _ewb?.sourceType,
      sourceId:     _ewb?.sourceId,
      sourceNumber: _ewb?.sourceNumber,
    ));
    if (ok == true) _load();
  }

  void _snack(String msg, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: c,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  static InputDecoration _inputDec(String label, String hint) => InputDecoration(
    labelText: label, hintText: hint, labelStyle: const TextStyle(fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    filled: true, fillColor: const Color(0xFFF7F9FC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [_navyDark, _navy], begin: Alignment.centerLeft, end: Alignment.centerRight)),
          child: AppBar(
            backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white,
            title: Text(_ewb?.ewbNumber ?? 'e-Way Bill', style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (_ewb != null) ...[
                // Print button
                if (_ewb!.ewbNumber != null)
                  _appBtn(_printing ? 'Printing…' : 'Print PDF',
                    _printing ? Icons.hourglass_top : Icons.print_outlined,
                    Colors.white70, _printing ? null : _printPDF),
                if (_ewb!.isActive || _ewb!.isPartA)
                  _appBtn('Update Vehicle', Icons.local_shipping_outlined, Colors.white70, _showUpdateVehicle),
                if (_ewb!.canExtend)
                  _appBtn('Extend', Icons.timer_outlined, Colors.white70, _showExtend),
                if (_ewb!.canCancel)
                  _appBtn('Cancel EWB', Icons.cancel_outlined, const Color(0xFFFF9999), _showCancel),
                // More menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  itemBuilder: (_) => [
                    _menuItem('associate', Icons.link, _blue, 'Associate Manual EWB'),
                    _menuItem('consolidate', Icons.merge_type, _purple, 'Consolidated EWB'),
                  ],
                  onSelected: (v) {
                    if (v == 'associate')   _showAssociate();
                    if (v == 'consolidate') Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsolidatedEWBForm()));
                  },
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: _navy))
        : _ewb == null
          ? const Center(child: Text('EWB not found', style: TextStyle(fontSize: 16, color: Colors.grey)))
          : _buildBody(),
    );
  }

  Widget _appBtn(String label, IconData icon, Color color, VoidCallback? onTap) =>
    TextButton.icon(onPressed: onTap,
      icon: Icon(icon, size: 15, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)));

  PopupMenuItem<String> _menuItem(String v, IconData icon, Color c, String label) =>
    PopupMenuItem(value: v, child: ListTile(
      leading: Icon(icon, size: 17, color: c),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      contentPadding: EdgeInsets.zero, dense: true));

  Widget _buildBody() {
    final ewb = _ewb!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        final isWide = c.maxWidth > 800;
        if (isWide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: Column(children: [
              _buildHeader(ewb), const SizedBox(height: 16),
              _buildPartA(ewb),  const SizedBox(height: 16),
              _buildGoods(ewb),
            ])),
            const SizedBox(width: 16),
            Expanded(child: Column(children: [
              _buildTransport(ewb), const SizedBox(height: 16),
              _buildPartB(ewb),
            ])),
          ]);
        }
        return Column(children: [
          _buildHeader(ewb),    const SizedBox(height: 16),
          _buildPartA(ewb),     const SizedBox(height: 16),
          _buildGoods(ewb),     const SizedBox(height: 16),
          _buildTransport(ewb), const SizedBox(height: 16),
          _buildPartB(ewb),
        ]);
      }),
    );
  }

  Widget _buildHeader(EWayBillModel ewb) {
    const statusColors = <String, List<Color>>{
      'GENERATED': [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'PART_A':    [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'EXTENDED':  [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'EXPIRED':   [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'CANCELLED': [Color(0xFFF1F5F9), Color(0xFF64748B)],
    };
    final c = statusColors[ewb.ewbStatus] ?? [const Color(0xFFF1F5F9), const Color(0xFF94A3B8)];
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_navyDark, _navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ewb.ewbNumber ?? 'Part A Generated', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${ewb.sourceType.replaceAll('_', ' ')} · ${ewb.sourceNumber}',
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20)),
            child: Text(ewb.ewbStatus.replaceAll('_', ' '), style: TextStyle(color: c[1], fontWeight: FontWeight.bold, fontSize: 12))),
        ]),
        if (ewb.ewbDate != null || ewb.validUntil != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            if (ewb.ewbDate != null) Expanded(child: _hTile('Generated', DateFormat('dd MMM yyyy HH:mm').format(ewb.ewbDate!), Colors.white)),
            if (ewb.validUntil != null) Expanded(child: _hTile('Valid Until', DateFormat('dd MMM yyyy').format(ewb.validUntil!),
              ewb.isExpired ? const Color(0xFFFF6B6B) : const Color(0xFF98FF98))),
            if (ewb.validUntil != null) Expanded(child: _hTile('Status', ewb.validityText, Colors.white)),
          ]),
        ],
        // Print button inline
        if (ewb.ewbNumber != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _printing ? null : _printPDF,
              icon: _printing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 16, color: Colors.white70),
              label: Text(_printing ? 'Generating PDF…' : 'Download PDF',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _hTile(String label, String value, Color vc) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
    const SizedBox(height: 3),
    Text(value, style: TextStyle(color: vc, fontWeight: FontWeight.w600, fontSize: 13)),
  ]);

  Widget _buildPartA(EWayBillModel ewb) => _detCard('Part A — From & To', Icons.swap_horiz_rounded, [
    _dr('Supply Type', ewb.supplyType), _dr('Sub Type', ewb.subType.replaceAll('_', ' ')),
    const Divider(height: 20),
    const Text('FROM', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 12)), const SizedBox(height: 6),
    _dr('GSTIN', ewb.fromGstin), _dr('Name', ewb.fromTradeName), _dr('Place', '${ewb.fromPlace}, ${ewb.fromState}'),
    const Divider(height: 20),
    const Text('TO', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 12)), const SizedBox(height: 6),
    _dr('GSTIN', ewb.toGstin), _dr('Name', ewb.toTradeName), _dr('Place', '${ewb.toPlace}, ${ewb.toState}'),
  ]);

  Widget _buildGoods(EWayBillModel ewb) => _detCard('Goods Details', Icons.inventory_2_outlined, [
    _dr('HSN',      ewb.hsnCode), _dr('Product', ewb.productName),
    _dr('Quantity', '${ewb.quantity} ${ewb.unit}'),
    _dr('Taxable',  '₹${ewb.taxableAmount.toStringAsFixed(2)}'),
    if (ewb.cgstRate > 0) _dr('CGST', '${ewb.cgstRate}%'),
    if (ewb.sgstRate > 0) _dr('SGST', '${ewb.sgstRate}%'),
    if (ewb.igstRate > 0) _dr('IGST', '${ewb.igstRate}%'),
    _dr('Total', '₹${ewb.totalInvoiceValue.toStringAsFixed(2)}'),
  ]);

  Widget _buildTransport(EWayBillModel ewb) => _detCard('Transport Details', Icons.local_shipping_outlined, [
    _dr('Mode',     ewb.transportMode),
    _dr('Distance', '${ewb.approximateDistance.toStringAsFixed(0)} km'),
    if (ewb.transporterName.isNotEmpty) _dr('Transporter', ewb.transporterName),
    if (ewb.transporterId.isNotEmpty)   _dr('TRANSIN', ewb.transporterId),
  ]);

  Widget _buildPartB(EWayBillModel ewb) {
    if (ewb.vehicleNumber.isEmpty && !ewb.isPartA) return const SizedBox.shrink();
    if (ewb.isPartA || ewb.vehicleNumber.isEmpty) {
      return Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber[300]!)),
        child: const Row(children: [
          Icon(Icons.pending_actions, color: Colors.amber, size: 20), SizedBox(width: 10),
          Expanded(child: Text('Part B not filled yet — transporter needs to update vehicle details.', style: TextStyle(fontSize: 13))),
        ]));
    }
    return _detCard('Part B — Vehicle', Icons.directions_car_outlined, [
      _dr('Vehicle No.',   ewb.vehicleNumber),
      _dr('Vehicle Type',  ewb.vehicleType.replaceAll('_', ' ')),
      if (ewb.fromPlacePartB.isNotEmpty) _dr('From Place', ewb.fromPlacePartB),
    ]);
  }

  Widget _detCard(String title, IconData icon, List<Widget> rows) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: _navyDark.withOpacity(0.04),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(gradient: const LinearGradient(colors: [_navyDark, _navy]), borderRadius: BorderRadius.circular(5)),
            child: Icon(icon, color: Colors.white, size: 14)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navyDark)),
        ])),
      Padding(padding: const EdgeInsets.all(16), child: Column(children: rows)),
    ]));

  Widget _dr(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
      Expanded(child: Text(value.isNotEmpty ? value : '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
    ]));
}