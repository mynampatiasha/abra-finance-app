// ============================================================================
// ABRA FLEET — CREATE / EDIT RATE CARD SCREEN
// ============================================================================
// File: lib/screens/rate_card/create_rate_card.dart
//
// MODES:
//   CREATE — CreateRateCardScreen(authToken: token)
//   EDIT   — CreateRateCardScreen(authToken: token, existingCard: cardData)
//
// RESPONSIVE:
//   Mobile  < 600px  → single column, full-width
//   Tablet  600-900  → 2-column fields, 24px padding
//   Desktop > 900px  → 3-column fields, 48px padding, max-width 960px
//
// NAVIGATION:
//   On save (create) → Navigator.pop with {'created': true, 'data': card}
//   On save (edit)   → Navigator.pop with {'updated': true, 'data': card}
//   Detail screen catches result and calls _loadCard() to refresh
//
// API:
//   CREATE → POST /api/rate-cards
//   EDIT   → PUT  /api/rate-cards/:id
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../app/config/api_config.dart';

// ── API Service ──────────────────────────────────────────────────────────
class ApiService {
  // ✅ Use centralized API configuration instead of hardcoded URL
  static String get base => ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> post(
    String ep, Map<String, dynamic> body, {String? token}) async {
    final r = await http.post(Uri.parse('$base$ep'),
        headers: _h(token), body: jsonEncode(body));
    return jsonDecode(r.body);
  }

  static Future<Map<String, dynamic>> put(
    String ep, Map<String, dynamic> body, {String? token}) async {
    final r = await http.put(Uri.parse('$base$ep'),
        headers: _h(token), body: jsonEncode(body));
    return jsonDecode(r.body);
  }

  static Future<Map<String, dynamic>> get(
    String ep, {String? token}) async {
    final r = await http.get(Uri.parse('$base$ep'), headers: _h(token));
    return jsonDecode(r.body);
  }

  static Map<String, String> _h(String? token) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

// ── Brand Colors ─────────────────────────────────────────────────────────
class AC {
  static const navyDark   = Color(0xFF0A1628);
  static const navy       = Color(0xFF1A2744);
  static const blueMid    = Color(0xFF1E3A8A);
  static const blue       = Color(0xFF2563EB);
  static const blueLight  = Color(0xFFEFF6FF);
  static const blueBorder = Color(0xFFBFDBFE);
  static const green      = Color(0xFF22C55E);
  static const red        = Color(0xFFE74C3C);
  static const amber      = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFEF3C7);
  static const bg         = Color(0xFFF0F5FB);
  static const card       = Color(0xFFFFFFFF);
  static const border     = Color(0xFFDDE5F0);
  static const textDark   = Color(0xFF1E293B);
  static const textMid    = Color(0xFF475569);
  static const textLight  = Color(0xFF94A3B8);
}

// ── Responsive helper ─────────────────────────────────────────────────────
class _R {
  final double w;
  _R(this.w);
  bool   get isMobile  => w < 600;
  bool   get isTablet  => w >= 600 && w < 900;
  bool   get isDesktop => w >= 900;
  double get hPad      => isDesktop ? 48 : isTablet ? 24 : 16;
  double get maxW      => isDesktop ? 960 : double.infinity;
}

// ── Constants ─────────────────────────────────────────────────────────────
const List<String> kVehicleTypes = [
  'SEDAN','SUV','INNOVA_CRYSTA','TEMPO_TRAVELLER_12',
  'MINI_BUS_20','LARGE_BUS_55','LUXURY_BMW','LUXURY_MERCEDES','LUXURY_AUDI',
];
const Map<String,String> kVehicleLabels = {
  'SEDAN':'Sedan (Dzire/Amaze)','SUV':'SUV (Ertiga/Safari)',
  'INNOVA_CRYSTA':'Innova Crysta','TEMPO_TRAVELLER_12':'Tempo Traveller (12)',
  'MINI_BUS_20':'Mini Bus (20)','LARGE_BUS_55':'Large Bus (55)',
  'LUXURY_BMW':'Luxury BMW','LUXURY_MERCEDES':'Luxury Mercedes','LUXURY_AUDI':'Luxury Audi',
};
const List<String> kBillingModels = [
  'PER_KM','PER_TRIP_FIXED','DEDICATED_MONTHLY','HYBRID',
];
const Map<String,String> kBillingModelLabels = {
  'PER_KM':'Per KM','PER_TRIP_FIXED':'Per Trip (Fixed)',
  'DEDICATED_MONTHLY':'Dedicated Monthly','HYBRID':'Hybrid (Monthly + Excess KM)',
};

// ── Vehicle Rate Row ──────────────────────────────────────────────────────
class VehicleRateRow {
  String vehicleType  = 'SEDAN';
  String billingModel = 'PER_KM';
  final ratePerKm           = TextEditingController();
  final minimumKmPerTrip    = TextEditingController();
  final ratePerTrip         = TextEditingController();
  final monthlyRate         = TextEditingController();
  final includedKmPerMonth  = TextEditingController();
  final hybridMonthlyBase   = TextEditingController();
  final hybridIncludedKm    = TextEditingController();
  final hybridExcessRate    = TextEditingController();
  final minimumTripsPerMonth= TextEditingController();

  void fromJson(Map<String,dynamic> d) {
    vehicleType  = d['vehicleType']  ?? 'SEDAN';
    billingModel = d['billingModel'] ?? 'PER_KM';
    _s(ratePerKm,           d['ratePerKm']);
    _s(minimumKmPerTrip,    d['minimumKmPerTrip']);
    _s(ratePerTrip,         d['ratePerTrip']);
    _s(monthlyRate,         d['monthlyRate']);
    _s(includedKmPerMonth,  d['includedKmPerMonth']);
    _s(hybridMonthlyBase,   d['hybridMonthlyBase']);
    _s(hybridIncludedKm,    d['hybridIncludedKm']);
    _s(hybridExcessRate,    d['hybridExcessRatePerKm']);
    _s(minimumTripsPerMonth,d['minimumTripsPerMonth']);
  }

  void _s(TextEditingController c, dynamic v) {
    if (v != null && v != 0 && v != 0.0) c.text = v.toString();
  }

  void dispose() {
    ratePerKm.dispose(); minimumKmPerTrip.dispose(); ratePerTrip.dispose();
    monthlyRate.dispose(); includedKmPerMonth.dispose();
    hybridMonthlyBase.dispose(); hybridIncludedKm.dispose();
    hybridExcessRate.dispose(); minimumTripsPerMonth.dispose();
  }

  Map<String,dynamic> toJson() => {
    'vehicleType': vehicleType, 'billingModel': billingModel,
    'ratePerKm':             _n(ratePerKm.text),
    'minimumKmPerTrip':      _n(minimumKmPerTrip.text),
    'ratePerTrip':           _n(ratePerTrip.text),
    'monthlyRate':           _n(monthlyRate.text),
    'includedKmPerMonth':    _n(includedKmPerMonth.text),
    'hybridMonthlyBase':     _n(hybridMonthlyBase.text),
    'hybridIncludedKm':      _n(hybridIncludedKm.text),
    'hybridExcessRatePerKm': _n(hybridExcessRate.text),
    'minimumTripsPerMonth':  _n(minimumTripsPerMonth.text),
    'isActive': true,
  };
  double _n(String s) => double.tryParse(s.trim()) ?? 0;
}

// ============================================================================
// SCREEN
// ============================================================================

class CreateRateCardScreen extends StatefulWidget {
  final String?               authToken;
  /// Pass existing card data to enter EDIT mode. null = CREATE mode.
  final Map<String,dynamic>?  existingCard;

  const CreateRateCardScreen({Key? key, this.authToken, this.existingCard})
      : super(key: key);

  @override
  State<CreateRateCardScreen> createState() => _CRCState();
}

class _CRCState extends State<CreateRateCardScreen> {

  bool get _isEdit  => widget.existingCard != null;
  String get _rcId  => widget.existingCard?['_id'] ?? '';

  final _fKey   = GlobalKey<FormState>();
  bool  _saving = false;
  int   _step   = 0;

  // Step 0 ─────────────────────────────────────────────────────────
  final _orgName       = TextEditingController();
  final _domain        = TextEditingController();
  final _billingEmail  = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactPhone  = TextEditingController();
  final _gstNumber     = TextEditingController();
  final _street        = TextEditingController();
  final _city          = TextEditingController();
  final _stateCtrl     = TextEditingController();
  final _pincode       = TextEditingController();
  DateTime? _cStart;
  DateTime? _cEnd;
  String _billingCycle = 'MONTHLY';
  String _paymentTerms = 'Net 30';
  final _creditDays    = TextEditingController(text: '30');
  final _gstPct        = TextEditingController(text: '5');
  final _tdsPct        = TextEditingController(text: '1');

  // Step 1 ─────────────────────────────────────────────────────────
  List<VehicleRateRow> _vRates = [VehicleRateRow()];

  // Step 2 ─────────────────────────────────────────────────────────
  bool   _nightOn   = false;
  final  _nightSH   = TextEditingController(text: '22');
  final  _nightEH   = TextEditingController(text: '6');
  final  _nightAmt  = TextEditingController(text: '0');
  bool   _weekendOn = false;
  final  _wkPct     = TextEditingController(text: '0');
  bool   _festOn    = false;
  final  _festDates = TextEditingController();
  final  _festPct   = TextEditingController(text: '0');
  bool   _waitOn    = false;
  final  _waitFree  = TextEditingController(text: '10');
  final  _waitRate  = TextEditingController(text: '0');
  String _tollType  = 'ACTUALS';
  final  _tollFlat  = TextEditingController(text: '0');
  bool   _escortOn  = false;
  final  _escortAmt = TextEditingController(text: '0');

  // Step 3 ─────────────────────────────────────────────────────────
  final _onTimePct = TextEditingController(text: '95');
  final _l1        = TextEditingController(text: '10');
  final _l2        = TextEditingController(text: '20');
  final _l3        = TextEditingController(text: '30');
  final _penAmt    = TextEditingController(text: '0');
  final _maxPen    = TextEditingController(text: '0');
  final _notes     = TextEditingController();

  final _steps = ['Organisation','Vehicle Rates','Surcharges','SLA & Submit'];

  // ── Init ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    if (_isEdit) _prefill(widget.existingCard!);
  }

  void _prefill(Map<String,dynamic> d) {
    _orgName.text      = d['organizationName']  ?? '';
    _domain.text       = d['domain']            ?? '';
    _billingEmail.text = d['billingEmail']       ?? '';
    _contactPerson.text= d['contactPersonName'] ?? '';
    _contactPhone.text = d['contactPersonPhone']?? '';
    _gstNumber.text    = d['gstNumber']         ?? '';
    _creditDays.text   = (d['creditPeriodDays'] ?? 30).toString();
    _gstPct.text       = (d['gstPercent']       ?? 5).toString();
    _tdsPct.text       = (d['tdsPercent']       ?? 1).toString();
    _billingCycle      = d['billingCycle']       ?? 'MONTHLY';
    _paymentTerms      = d['paymentTerms']       ?? 'Net 30';
    _notes.text        = d['internalNotes']     ?? '';
    if (d['contractStartDate'] != null)
      _cStart = DateTime.tryParse(d['contractStartDate'].toString());
    if (d['contractEndDate'] != null)
      _cEnd = DateTime.tryParse(d['contractEndDate'].toString());

    final addr = d['billingAddress'] as Map<String,dynamic>? ?? {};
    _street.text   = addr['street']  ?? '';
    _city.text     = addr['city']    ?? '';
    _stateCtrl.text= addr['state']   ?? '';
    _pincode.text  = addr['pincode'] ?? '';

    final rates = d['vehicleRates'] as List? ?? [];
    if (rates.isNotEmpty) {
      for (final r in _vRates) r.dispose();
      _vRates = rates.map((r) {
        final row = VehicleRateRow();
        row.fromJson(r as Map<String,dynamic>);
        return row;
      }).toList();
    }

    final s = d['surchargeRules'] as Map<String,dynamic>? ?? {};
    _nightOn       = s['nightShiftEnabled']  == true;
    _nightSH.text  = (s['nightStartHour']    ?? 22).toString();
    _nightEH.text  = (s['nightEndHour']      ?? 6).toString();
    _nightAmt.text = (s['nightSurchargePerTrip'] ?? 0).toString();
    _weekendOn     = s['weekendEnabled']      == true;
    _wkPct.text    = (s['weekendSurchargePercent'] ?? 0).toString();
    _festOn        = s['festivalEnabled']     == true;
    _festDates.text= ((s['festivalDates'] as List?) ?? []).join(', ');
    _festPct.text  = (s['festivalSurchargePercent'] ?? 0).toString();
    _waitOn        = s['waitingEnabled']      == true;
    _waitFree.text = (s['waitingFreeMinutes'] ?? 10).toString();
    _waitRate.text = (s['waitingRatePerMinute']?? 0).toString();
    _tollType      = s['tollType']            ?? 'ACTUALS';
    _tollFlat.text = (s['tollFlatRatePerTrip']?? 0).toString();
    _escortOn      = s['escortEnabled']       == true;
    _escortAmt.text= (s['escortSurchargePerTrip'] ?? 0).toString();

    final sla = d['slaTerms'] as Map<String,dynamic>? ?? {};
    _onTimePct.text= (sla['onTimePickupPercent']    ?? 95).toString();
    _l1.text       = (sla['l1EscalationMinutes']    ?? 10).toString();
    _l2.text       = (sla['l2EscalationMinutes']    ?? 20).toString();
    _l3.text       = (sla['l3EscalationMinutes']    ?? 30).toString();
    _penAmt.text   = (sla['penaltyPerBreachAmount'] ?? 0).toString();
    _maxPen.text   = (sla['maxPenaltyPerMonth']     ?? 0).toString();
  }

  @override
  void dispose() {
    _orgName.dispose(); _domain.dispose(); _billingEmail.dispose();
    _contactPerson.dispose(); _contactPhone.dispose(); _gstNumber.dispose();
    _street.dispose(); _city.dispose(); _stateCtrl.dispose(); _pincode.dispose();
    _creditDays.dispose(); _gstPct.dispose(); _tdsPct.dispose();
    for (final r in _vRates) r.dispose();
    _nightSH.dispose(); _nightEH.dispose(); _nightAmt.dispose();
    _wkPct.dispose(); _festDates.dispose(); _festPct.dispose();
    _waitFree.dispose(); _waitRate.dispose(); _tollFlat.dispose();
    _escortAmt.dispose(); _onTimePct.dispose(); _l1.dispose();
    _l2.dispose(); _l3.dispose(); _penAmt.dispose(); _maxPen.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ── Payload ───────────────────────────────────────────────────────
  Map<String,dynamic> _payload() {
    final festList = _festDates.text
        .split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return {
      'organizationName':   _orgName.text.trim(),
      'domain':             _domain.text.trim().toLowerCase(),
      'billingEmail':       _billingEmail.text.trim(),
      'contactPersonName':  _contactPerson.text.trim(),
      'contactPersonPhone': _contactPhone.text.trim(),
      'gstNumber':          _gstNumber.text.trim(),
      'billingAddress': {
        'street': _street.text.trim(), 'city': _city.text.trim(),
        'state': _stateCtrl.text.trim(), 'pincode': _pincode.text.trim(),
        'country': 'India',
      },
      'contractStartDate': _cStart?.toIso8601String(),
      'contractEndDate':   _cEnd?.toIso8601String(),
      'billingCycle': _billingCycle, 'paymentTerms': _paymentTerms,
      'creditPeriodDays': int.tryParse(_creditDays.text) ?? 30,
      'gstPercent': double.tryParse(_gstPct.text) ?? 5,
      'tdsPercent': double.tryParse(_tdsPct.text) ?? 1,
      'vehicleRates': _vRates.map((r) => r.toJson()).toList(),
      'surchargeRules': {
        'nightShiftEnabled':        _nightOn,
        'nightStartHour':           int.tryParse(_nightSH.text) ?? 22,
        'nightEndHour':             int.tryParse(_nightEH.text) ?? 6,
        'nightSurchargePerTrip':    double.tryParse(_nightAmt.text) ?? 0,
        'weekendEnabled':           _weekendOn,
        'weekendSurchargePercent':  double.tryParse(_wkPct.text) ?? 0,
        'festivalEnabled':          _festOn,
        'festivalDates':            festList,
        'festivalSurchargePercent': double.tryParse(_festPct.text) ?? 0,
        'waitingEnabled':           _waitOn,
        'waitingFreeMinutes':       int.tryParse(_waitFree.text) ?? 10,
        'waitingRatePerMinute':     double.tryParse(_waitRate.text) ?? 0,
        'tollType':                 _tollType,
        'tollFlatRatePerTrip':      double.tryParse(_tollFlat.text) ?? 0,
        'escortEnabled':            _escortOn,
        'escortSurchargePerTrip':   double.tryParse(_escortAmt.text) ?? 0,
      },
      'slaTerms': {
        'onTimePickupPercent':    double.tryParse(_onTimePct.text) ?? 95,
        'l1EscalationMinutes':    int.tryParse(_l1.text) ?? 10,
        'l2EscalationMinutes':    int.tryParse(_l2.text) ?? 20,
        'l3EscalationMinutes':    int.tryParse(_l3.text) ?? 30,
        'penaltyPerBreachAmount': double.tryParse(_penAmt.text) ?? 0,
        'maxPenaltyPerMonth':     double.tryParse(_maxPen.text) ?? 0,
      },
      'internalNotes': _notes.text.trim(),
      if (!_isEdit) 'status': 'DRAFT',
    };
  }

  // ── Submit ────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_fKey.currentState!.validate()) return;
    if (_cStart == null || _cEnd == null) {
      _err('Please select contract start and end dates'); return;
    }
    setState(() => _saving = true);
    try {
      final data = _payload();
      final res  = _isEdit
          ? await ApiService.put('/api/rate-cards/$_rcId', data, token: widget.authToken)
          : await ApiService.post('/api/rate-cards', data, token: widget.authToken);

      if (res['success'] == true) {
        if (!mounted) return;
        // ── Return result to caller (detail screen) ───────────────
        Navigator.of(context).pop(
          _isEdit
              ? {'updated': true, 'data': res['data']}
              : {'created': true, 'data': res['data']},
        );
      } else {
        _err(res['error'] ?? 'Failed to save');
      }
    } catch (e) {
      _err('Network error: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg), backgroundColor: AC.red,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ));

  // ══════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final r = _R(box.maxWidth);
      return Scaffold(
        backgroundColor: AC.bg,
        appBar: _bar(),
        body: Column(children: [
          _stepBar(r),
          Expanded(
            child: Form(
              key: _fKey,
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: r.maxW),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(r.hPad, 16, r.hPad, 32),
                      child: _body(r),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _navBar(r),
        ]),
      );
    });
  }

  AppBar _bar() => AppBar(
    backgroundColor: AC.navyDark, foregroundColor: Colors.white,
    elevation: 0,
    title: Text(
      _isEdit ? 'Edit Rate Card' : 'Create Rate Card',
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
    ),
    actions: [
      Container(
        margin: const EdgeInsets.only(right: 10, top: 10, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: (_isEdit ? AC.blue : AC.amber).withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: (_isEdit ? AC.blue : AC.amber).withOpacity(0.5)),
        ),
        child: Center(child: Text(
          _isEdit ? 'EDIT MODE' : 'DRAFT',
          style: TextStyle(
            color: _isEdit ? AC.blue : AC.amber,
            fontSize: 10, fontWeight: FontWeight.w800),
        )),
      ),
    ],
  );

  // ── Step Bar ──────────────────────────────────────────────────────
  Widget _stepBar(_R r) => Container(
    color: AC.navy,
    padding: EdgeInsets.symmetric(vertical: 12, horizontal: r.hPad),
    child: Row(
      children: List.generate(_steps.length, (i) {
        final done = i < _step, cur = i == _step;
        return Expanded(child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: () { if (i <= _step) setState(() => _step = i); },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AC.green : cur ? AC.blue : Colors.white.withOpacity(0.15)),
                child: Center(child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('${i+1}', style: TextStyle(
                        color: cur ? Colors.white : Colors.white38,
                        fontSize: 11, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 3),
              if (!r.isMobile || cur)
                Text(_steps[i], overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cur ? Colors.white : Colors.white38,
                      fontSize: r.isMobile ? 8 : 10,
                      fontWeight: cur ? FontWeight.w700 : FontWeight.normal)),
            ]),
          )),
          if (i < _steps.length - 1)
            Container(height: 2, width: r.isMobile ? 10 : 18,
                margin: const EdgeInsets.only(bottom: 14),
                color: done ? AC.green.withOpacity(0.5) : Colors.white.withOpacity(0.15)),
        ]));
      }),
    ),
  );

  Widget _body(_R r) {
    switch (_step) {
      case 0: return _orgStep(r);
      case 1: return _vehicleStep(r);
      case 2: return _surchargeStep(r);
      case 3: return _slaStep(r);
      default: return const SizedBox();
    }
  }

  // ── Bottom Nav Bar ────────────────────────────────────────────────
  Widget _navBar(_R r) => Container(
    padding: EdgeInsets.fromLTRB(r.hPad, 12, r.hPad, 20),
    decoration: BoxDecoration(
      color: AC.card,
      border: Border(top: BorderSide(color: AC.border)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
          blurRadius: 8, offset: const Offset(0, -2))],
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: r.maxW),
        child: Row(children: [
          if (_step > 0) ...[
            Expanded(child: OutlinedButton(
              onPressed: () => setState(() => _step--),
              style: OutlinedButton.styleFrom(
                foregroundColor: AC.blueMid,
                side: const BorderSide(color: AC.blueMid),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('← Back', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 12),
          ],
          Expanded(flex: 2, child: _step < _steps.length - 1
              ? ElevatedButton(
                  onPressed: () => setState(() => _step++),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AC.blue, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text('Next: ${_steps[_step+1]} →',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                )
              : ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AC.green, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? '✓ Save Changes' : '✓ Save Rate Card',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
          ),
        ]),
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════
  // STEP 0
  // ══════════════════════════════════════════════════════════════════

  Widget _orgStep(_R r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sh('Organisation & Contract', Icons.business_outlined),
    _card([
      _row(r, [
        _field('Organisation Name', _orgName, req: true, hint: 'Infosys Limited',
            icon: Icons.business_outlined),
        _field('Domain', _domain, req: true, hint: 'infosys.com',
            icon: Icons.language, readOnly: _isEdit,
            helper: _isEdit ? '🔒 Domain cannot be changed in edit mode'
                            : 'Links all trips to this rate card'),
      ]),
      _row(r, [
        _field('Billing Email', _billingEmail, req: true, hint: 'billing@infosys.com',
            icon: Icons.email_outlined, kt: TextInputType.emailAddress),
        _field('Contact Person', _contactPerson, hint: 'Full Name',
            icon: Icons.person_outline),
      ]),
      _row(r, [
        _field('Contact Phone', _contactPhone, hint: '+91 XXXXX XXXXX',
            icon: Icons.phone_outlined, kt: TextInputType.phone),
        _field('GST Number', _gstNumber, hint: '29XXXXXXXXX',
            icon: Icons.receipt_outlined),
      ]),
    ]),

    _sh('Contract Period', Icons.calendar_today_outlined),
    _card([
      _row(r, [
        _datePick('Contract Start *', _cStart, (d) => setState(() => _cStart = d)),
        _datePick('Contract End *',   _cEnd,   (d) => setState(() => _cEnd = d)),
      ]),
      const SizedBox(height: 14),
      _row(r, [
        _dd('Billing Cycle', _billingCycle, ['MONTHLY','FORTNIGHTLY','WEEKLY'],
            (v) => setState(() => _billingCycle = v!),
            lm: {'MONTHLY':'Monthly','FORTNIGHTLY':'Fortnightly','WEEKLY':'Weekly'}),
        _dd('Payment Terms', _paymentTerms,
            ['Due on Receipt','Net 15','Net 30','Net 45','Net 60'],
            (v) => setState(() => _paymentTerms = v!)),
      ]),
      _row(r, [
        _field('Credit Period (days)', _creditDays, hint: '30',
            icon: Icons.timer_outlined, kt: TextInputType.number,
            fmt: [FilteringTextInputFormatter.digitsOnly]),
        _field('GST %', _gstPct, hint: '5', icon: Icons.percent,
            kt: TextInputType.number),
        _field('TDS %', _tdsPct, hint: '1', icon: Icons.percent,
            kt: TextInputType.number),
      ]),
    ]),

    _sh('Billing Address', Icons.location_on_outlined),
    _card([
      _field('Street', _street, hint: '123 Main Road'),
      _row(r, [
        _field('City',    _city,     hint: 'Bengaluru'),
        _field('State',   _stateCtrl,hint: 'Karnataka'),
        _field('Pincode', _pincode,  hint: '560001', kt: TextInputType.number,
            fmt: [FilteringTextInputFormatter.digitsOnly]),
      ]),
    ]),
  ]);

  // ══════════════════════════════════════════════════════════════════
  // STEP 1
  // ══════════════════════════════════════════════════════════════════

  Widget _vehicleStep(_R r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sh('Vehicle Rate Matrix', Icons.directions_car_outlined),
    _banner('One row per vehicle type. Fields shown change based on billing model selected.'),
    ..._vRates.asMap().entries.map((e) => _vCard(r, e.key, e.value)),
    const SizedBox(height: 4),
    SizedBox(width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _vRates.add(VehicleRateRow())),
        icon: const Icon(Icons.add, color: AC.blue),
        label: const Text('Add Vehicle Type',
            style: TextStyle(color: AC.blue, fontWeight: FontWeight.w800)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AC.blue, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
  ]);

  Widget _vCard(_R r, int i, VehicleRateRow row) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: AC.card, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AC.border),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
    ),
    child: Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AC.navy,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [
          const Icon(Icons.directions_car, color: Colors.white60, size: 16),
          const SizedBox(width: 8),
          Text('Vehicle ${i+1}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (_vRates.length > 1)
            GestureDetector(
              onTap: () { row.dispose(); setState(() => _vRates.removeAt(i)); },
              child: const Icon(Icons.delete_outline, color: Colors.white54, size: 20)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          _row(r, [
            _ddInline('Vehicle Type', row.vehicleType, kVehicleTypes,
                (v) => setState(() => row.vehicleType = v!), lm: kVehicleLabels),
            _ddInline('Billing Model', row.billingModel, kBillingModels,
                (v) => setState(() => row.billingModel = v!), lm: kBillingModelLabels),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AC.blueLight, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              if (row.billingModel == 'PER_KM')
                _row(r, [
                  _inline('Rate per KM (₹)', row.ratePerKm, hint: '25.00'),
                  _inline('Min KM per Trip',  row.minimumKmPerTrip, hint: '10'),
                ]),
              if (row.billingModel == 'PER_TRIP_FIXED')
                _inline('Rate per Trip (₹)', row.ratePerTrip, hint: '500.00'),
              if (row.billingModel == 'DEDICATED_MONTHLY')
                _row(r, [
                  _inline('Monthly Rate (₹)',     row.monthlyRate, hint: '75000'),
                  _inline('Included KM / Month',  row.includedKmPerMonth, hint: '3000'),
                ]),
              if (row.billingModel == 'HYBRID') ...[
                _row(r, [
                  _inline('Monthly Base (₹)',  row.hybridMonthlyBase, hint: '50000'),
                  _inline('Included KM',       row.hybridIncludedKm,  hint: '2000'),
                ]),
                const SizedBox(height: 10),
                _inline('Excess KM Rate (₹/km)', row.hybridExcessRate, hint: '18.00'),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          _inline('Min Trips / Month (Guarantee)',
              row.minimumTripsPerMonth, hint: '0 = no guarantee'),
        ]),
      ),
    ]),
  );

  // ══════════════════════════════════════════════════════════════════
  // STEP 2
  // ══════════════════════════════════════════════════════════════════

  Widget _surchargeStep(_R r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sh('Surcharge Rules', Icons.add_circle_outline),
    _sBlock(r, icon: Icons.nights_stay, title: 'Night Shift Surcharge',
        sub: 'Extra charge for trips during night hours',
        on: _nightOn, toggle: (v) => setState(() => _nightOn = v),
        body: [
          _row(r, [
            _inline('Night Start (24h)', _nightSH, hint: '22'),
            _inline('Night End (24h)',   _nightEH, hint: '6'),
          ]),
          const SizedBox(height: 10),
          _inline('Surcharge per Trip (₹)', _nightAmt, hint: '150'),
        ]),
    _sBlock(r, icon: Icons.weekend, title: 'Weekend Surcharge',
        sub: 'Extra % on base amount — Sat & Sun',
        on: _weekendOn, toggle: (v) => setState(() => _weekendOn = v),
        body: [_inline('Surcharge % on Base', _wkPct, hint: '10')]),
    _sBlock(r, icon: Icons.celebration, title: 'Festival Surcharge',
        sub: 'Extra % on specified festival dates',
        on: _festOn, toggle: (v) => setState(() => _festOn = v),
        body: [
          _inline('Festival Dates (comma separated)', _festDates,
              hint: '2025-10-02, 2025-11-01', kt: TextInputType.text),
          const SizedBox(height: 10),
          _inline('Surcharge % on Base', _festPct, hint: '15'),
        ]),
    _sBlock(r, icon: Icons.timer, title: 'Waiting Charges',
        sub: 'Per-minute charge after grace period',
        on: _waitOn, toggle: (v) => setState(() => _waitOn = v),
        body: [_row(r, [
          _inline('Free Minutes',        _waitFree, hint: '10'),
          _inline('Rate per Minute (₹)', _waitRate, hint: '2'),
        ])]),
    // Toll
    _card([
      Row(children: [
        Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AC.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.toll, color: AC.amber, size: 20)),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Toll Charges', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          Text('How toll fees are handled', style: TextStyle(fontSize: 12, color: AC.textMid)),
        ])),
      ]),
      const SizedBox(height: 14),
      _row(r, [
        _tollOpt('ACTUALS',        'Actuals\n(reimbursed)'),
        _tollOpt('INCLUDED',       'Included\n(flat rate)'),
        _tollOpt('NOT_APPLICABLE', 'Not\nApplicable'),
      ]),
      if (_tollType == 'INCLUDED') ...[
        const SizedBox(height: 12),
        _inline('Flat Toll per Trip (₹)', _tollFlat, hint: '100'),
      ],
    ]),
    _sBlock(r, icon: Icons.security, title: 'Escort / Women-Only Surcharge',
        sub: 'Extra per trip when escort is required',
        on: _escortOn, toggle: (v) => setState(() => _escortOn = v),
        body: [_inline('Escort Surcharge per Trip (₹)', _escortAmt, hint: '200')]),
  ]);

  Widget _tollOpt(String val, String label) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _tollType = val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _tollType == val ? AC.blue : AC.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _tollType == val ? AC.blue : AC.border, width: 1.5)),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: _tollType == val ? Colors.white : AC.textMid)),
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════
  // STEP 3
  // ══════════════════════════════════════════════════════════════════

  Widget _slaStep(_R r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sh('SLA Terms', Icons.verified_outlined),
    _card([
      _field('On-Time Pickup Target (%)', _onTimePct, hint: '95'),
      const SizedBox(height: 4),
      const Text('Escalation Timelines (delay in minutes)',
          style: TextStyle(fontSize: 12, color: AC.textMid, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      _row(r, [
        _inline('L1 Alert (mins)', _l1, hint: '10'),
        _inline('L2 Alert (mins)', _l2, hint: '20'),
        _inline('L3 Alert (mins)', _l3, hint: '30'),
      ]),
      const SizedBox(height: 12),
      _row(r, [
        _inline('Penalty per Breach (₹)', _penAmt, hint: '500'),
        _inline('Max Penalty / Month (₹)',_maxPen,  hint: '10000'),
      ]),
    ]),
    _sh('Internal Notes', Icons.note_outlined),
    _card([
      TextFormField(
        controller: _notes, maxLines: 4,
        decoration: InputDecoration(
          hintText: 'Any internal notes or special conditions...',
          hintStyle: const TextStyle(color: AC.textLight, fontSize: 13),
          filled: true, fillColor: AC.bg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AC.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AC.blue, width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AC.border)),
        ),
      ),
    ]),
    _summaryCard(),
  ]);

  Widget _summaryCard() => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF0A1628), Color(0xFF1E3A8A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.summarize, color: Colors.white, size: 17),
        const SizedBox(width: 8),
        Text(_isEdit ? 'Editing Rate Card' : 'Rate Card Summary',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
      ]),
      const SizedBox(height: 14),
      _sr('Organisation', _orgName.text.isEmpty ? '—' : _orgName.text),
      _sr('Domain',       _domain.text.isEmpty  ? '—' : _domain.text),
      _sr('Billing Email',_billingEmail.text.isEmpty ? '—' : _billingEmail.text),
      _sr('Contract',     _cStart != null && _cEnd != null
          ? '${_fmt(_cStart!)} → ${_fmt(_cEnd!)}' : '— not set —'),
      _sr('Vehicle Types','${_vRates.length} configured'),
      _sr('GST / TDS',    '${_gstPct.text}% / ${_tdsPct.text}%'),
      if (!_isEdit) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.white38, size: 13),
            SizedBox(width: 8),
            Expanded(child: Text('Saved as DRAFT — activate from Rate Cards list.',
                style: TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
        ),
      ],
    ]),
  );

  Widget _sr(String l, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110, child: Text(l,
          style: const TextStyle(color: Colors.white38, fontSize: 12))),
      Expanded(child: Text(v,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
    ]),
  );

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  // ══════════════════════════════════════════════════════════════════
  // REUSABLE RESPONSIVE WIDGETS
  // ══════════════════════════════════════════════════════════════════

  Widget _row(_R r, List<Widget> kids) {
    if (r.isMobile) return Column(children: kids);
    final out = <Widget>[];
    for (int i = 0; i < kids.length; i++) {
      out.add(Expanded(child: kids[i]));
      if (i < kids.length - 1) out.add(const SizedBox(width: 12));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }

  Widget _sh(String t, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: AC.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AC.blue, size: 17)),
      const SizedBox(width: 10),
      Text(t, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: AC.navyDark)),
    ]),
  );

  Widget _card(List<Widget> kids) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AC.card, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AC.border),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
  );

  Widget _banner(String msg) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AC.blueLight, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AC.blueBorder)),
    child: Row(children: [
      const Icon(Icons.info_outline, color: AC.blue, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg,
          style: const TextStyle(color: AC.blueMid, fontSize: 12, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _field(String label, TextEditingController ctrl, {
    bool req = false, String? hint, IconData? icon, String? helper,
    TextInputType kt = TextInputType.text,
    List<TextInputFormatter>? fmt, bool readOnly = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: ctrl, keyboardType: kt,
          inputFormatters: fmt, readOnly: readOnly,
          style: TextStyle(color: readOnly ? AC.textMid : AC.textDark, fontSize: 15),
          decoration: InputDecoration(
            labelText: req ? '$label *' : label,
            hintText: hint, helperText: helper, helperMaxLines: 2,
            prefixIcon: icon != null ? Icon(icon, color: AC.textLight, size: 18) : null,
            suffixIcon: readOnly
                ? const Tooltip(message: 'Cannot edit in this mode',
                    child: Icon(Icons.lock_outline, color: AC.textLight, size: 15))
                : null,
            filled: true, fillColor: readOnly ? const Color(0xFFF5F8FF) : AC.bg,
            labelStyle: const TextStyle(color: AC.textMid, fontSize: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AC.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AC.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: readOnly ? AC.border : AC.blue, width: readOnly ? 1 : 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          validator: req ? (v) =>
              (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
        ),
      );

  Widget _inline(String label, TextEditingController ctrl, {
    String? hint, TextInputType kt = TextInputType.number,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: AC.textMid)),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl, keyboardType: kt,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AC.textLight, fontSize: 15),
            filled: true, fillColor: AC.bg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AC.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AC.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AC.blue, width: 2)),
          ),
        ),
        const SizedBox(height: 12),
      ]);

  Widget _dd(String label, String value, List<String> items,
      ValueChanged<String?> onChange, {Map<String,String>? lm}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          value: value, onChanged: onChange,
          decoration: InputDecoration(
            labelText: label, filled: true, fillColor: AC.bg,
            labelStyle: const TextStyle(color: AC.textMid, fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AC.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AC.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AC.blue, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          items: items.map((i) => DropdownMenuItem(
              value: i,
              child: Text(lm?[i] ?? i, style: const TextStyle(fontSize: 13)))).toList(),
        ),
      );

  Widget _ddInline(String label, String value, List<String> items,
      ValueChanged<String?> onChange, {Map<String,String>? lm}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: AC.textMid)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: value, onChanged: onChange, isExpanded: true,
          decoration: InputDecoration(
            filled: true, fillColor: AC.bg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AC.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AC.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AC.blue, width: 2)),
          ),
          items: items.map((i) => DropdownMenuItem(
              value: i,
              child: Text(lm?[i] ?? i,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis))).toList(),
        ),
        const SizedBox(height: 12),
      ]);

  Widget _datePick(String label, DateTime? val, ValueChanged<DateTime> pick) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: val ?? DateTime.now(),
              firstDate: DateTime(2020), lastDate: DateTime(2035),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AC.blue, onPrimary: Colors.white, surface: Colors.white)),
                child: child!),
            );
            if (d != null) pick(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: AC.bg, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: val != null ? AC.blue : AC.border)),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined,
                  color: val != null ? AC.blue : AC.textLight, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                val != null ? _fmt(val) : label,
                style: TextStyle(fontSize: 13,
                    color: val != null ? AC.textDark : AC.textLight,
                    fontWeight: val != null ? FontWeight.w700 : FontWeight.normal))),
            ]),
          ),
        ),
      );

  Widget _sBlock(_R r, {
    required IconData icon, required String title, required String sub,
    required bool on, required ValueChanged<bool> toggle,
    required List<Widget> body,
  }) =>
      _card([
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: on ? AC.blue.withOpacity(0.1) : AC.bg,
              borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: on ? AC.blue : AC.textLight, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                color: on ? AC.textDark : AC.textMid)),
            Text(sub, style: const TextStyle(fontSize: 11, color: AC.textMid)),
          ])),
          Switch(value: on, onChanged: toggle, activeColor: AC.blue),
        ]),
        if (on) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AC.blueLight, borderRadius: BorderRadius.circular(8)),
            child: Column(children: body)),
        ],
      ]);
}