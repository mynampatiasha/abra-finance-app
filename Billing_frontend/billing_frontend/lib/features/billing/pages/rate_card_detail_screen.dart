// ============================================================================
// ABRA FLEET — RATE CARD DETAIL SCREEN
// ============================================================================
// File: lib/screens/rate_card/rate_card_detail_screen.dart
//
// SECTIONS:
//   1. Header — RC ID, org, domain, status, quick actions
//   2. Organisation & Contract Info
//   3. Vehicle Rate Matrix
//   4. Surcharge Rules
//   5. SLA Terms
//   6. Contract Documents (upload + preview)
//   7. Trip Billing Summary (current month + per-trip list)
//   8. Invoice History
//
// API:
//   GET  /api/rate-cards/:id
//   GET  /api/rate-cards/active/:domain
//   POST /api/rate-cards/:id/activate
//   POST /api/rate-cards/:id/suspend
//   GET  /api/billing/trips/:domain?month=&year=
//   GET  /api/billing/invoices?domain=
//   POST /api/billing/generate-invoice
//   POST /api/billing/invoices/:id/approve
//   POST /api/billing/invoices/:id/send
//   POST /api/rate-cards/:id/upload-document
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
// Import create/edit screen — same file, or adjust path to your project
import 'create_rate_card.dart' show CreateRateCardScreen;
import '../../../../app/config/api_config.dart';

// ── Responsive helper ─────────────────────────────────────────────────────
class _R {
  final double w;
  _R(this.w);
  bool   get isMobile  => w < 600;
  bool   get isTablet  => w >= 600 && w < 900;
  bool   get isDesktop => w >= 900;
  double get hPad      => isDesktop ? 48 : isTablet ? 24 : 16;
  double get maxW      => isDesktop ? 960 : double.infinity;
  // Column count for info grids
  int    get infoCols  => isDesktop ? 3 : isTablet ? 2 : 1;
}

// ── API Service (same as create_rate_card.dart) ──────────────────────────
class ApiService {
  // ✅ Use centralized API configuration instead of hardcoded URL
  static String get base => ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> get(String ep, {String? token}) async {
    final r = await http.get(Uri.parse('$base$ep'),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'});
    return jsonDecode(r.body);
  }

  static Future<Map<String, dynamic>> post(String ep, Map<String, dynamic> body, {String? token}) async {
    final r = await http.post(Uri.parse('$base$ep'),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
        body: jsonEncode(body));
    return jsonDecode(r.body);
  }
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
  static const greenDark  = Color(0xFF16A34A);
  static const greenLight = Color(0xFFDCFCE7);
  static const red        = Color(0xFFE74C3C);
  static const redLight   = Color(0xFFFEE2E2);
  static const amber      = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFEF3C7);
  static const purple     = Color(0xFF7C3AED);
  static const purpleLight= Color(0xFFEDE9FE);
  static const bg         = Color(0xFFF0F5FB);
  static const card       = Color(0xFFFFFFFF);
  static const border     = Color(0xFFDDE5F0);
  static const textDark   = Color(0xFF1E293B);
  static const textMid    = Color(0xFF475569);
  static const textLight  = Color(0xFF94A3B8);
}

// ── Helpers ───────────────────────────────────────────────────────────────
String fmtDate(dynamic d) {
  if (d == null) return '—';
  try {
    return DateFormat('dd MMM yyyy').format(DateTime.parse(d.toString()));
  } catch (_) { return d.toString(); }
}

String fmtCurrency(dynamic n) {
  final v = (n is num) ? n.toDouble() : (double.tryParse(n?.toString() ?? '') ?? 0.0);
  return '₹${NumberFormat('#,##,##0.00').format(v)}';
}

String fmtNum(dynamic n) {
  final v = (n is num) ? n.toDouble() : (double.tryParse(n?.toString() ?? '') ?? 0.0);
  return NumberFormat('#,##,##0.##').format(v);
}

Color statusColor(String? s) {
  switch (s) {
    case 'ACTIVE':   return AC.green;
    case 'DRAFT':    return AC.amber;
    case 'EXPIRED':  return AC.red;
    case 'SUSPENDED':return AC.textMid;
    case 'APPROVED': return AC.green;
    case 'PENDING_FINANCE_APPROVAL': return AC.amber;
    case 'SENT':     return AC.blue;
    case 'PAID':     return AC.greenDark;
    case 'DISPUTED': return AC.red;
    default:         return AC.textLight;
  }
}

Color statusBg(String? s) {
  switch (s) {
    case 'ACTIVE':   return AC.greenLight;
    case 'DRAFT':    return AC.amberLight;
    case 'EXPIRED':  return AC.redLight;
    case 'SUSPENDED':return AC.bg;
    case 'APPROVED': return AC.greenLight;
    case 'PENDING_FINANCE_APPROVAL': return AC.amberLight;
    case 'SENT':     return AC.blueLight;
    case 'PAID':     return AC.greenLight;
    case 'DISPUTED': return AC.redLight;
    default:         return AC.bg;
  }
}

Color _tripStatusColor(String? s) {
  switch (s) {
    case 'completed':   return AC.green;
    case 'in_progress': return AC.blue;
    case 'assigned':    return AC.amber;
    case 'cancelled':   return AC.red;
    default:            return AC.navy;
  }
}

Color _tripStatusBg(String? s) {
  switch (s) {
    case 'completed':   return AC.greenLight;
    case 'in_progress': return AC.blueLight;
    case 'assigned':    return AC.amberLight;
    case 'cancelled':   return AC.redLight;
    default:            return AC.bg;
  }
}

const Map<String, String> kVehicleLabels = {
  'SEDAN':              'Sedan',
  'SUV':                'SUV',
  'INNOVA_CRYSTA':      'Innova Crysta',
  'TEMPO_TRAVELLER_12': 'Tempo Traveller (12)',
  'MINI_BUS_20':        'Mini Bus (20)',
  'LARGE_BUS_55':       'Large Bus (55)',
  'LUXURY_BMW':         'BMW Luxury',
  'LUXURY_MERCEDES':    'Mercedes Luxury',
  'LUXURY_AUDI':        'Audi Luxury',
};

const Map<String, String> kBillingModelLabels = {
  'PER_KM':            'Per KM',
  'PER_TRIP_FIXED':    'Per Trip (Fixed)',
  'DEDICATED_MONTHLY': 'Dedicated Monthly',
  'HYBRID':            'Hybrid',
};

const Map<String, IconData> kBillingModelIcons = {
  'PER_KM':            Icons.speed,
  'PER_TRIP_FIXED':    Icons.confirmation_number_outlined,
  'DEDICATED_MONTHLY': Icons.calendar_month,
  'HYBRID':            Icons.merge_type,
};

// ── Info grid item (used for responsive tablet/desktop layouts) ───────────
class _InfoItem {
  final String  label;
  final dynamic value;
  final Color?  highlight;
  const _InfoItem(this.label, this.value, {this.highlight});
}

// ── Column definition for trips table ─────────────────────────────────────
class _ColDef {
  final String label;
  final double width;
  const _ColDef(this.label, this.width);
}

// ============================================================================
// MAIN SCREEN
// ============================================================================

class RateCardDetailScreen extends StatefulWidget {
  final String rateCardId;
  final String? authToken;

  const RateCardDetailScreen({
    Key? key,
    required this.rateCardId,
    this.authToken,
  }) : super(key: key);

  @override
  State<RateCardDetailScreen> createState() => _RateCardDetailScreenState();
}

class _RateCardDetailScreenState extends State<RateCardDetailScreen>
    with TickerProviderStateMixin {

  Map<String, dynamic>? _card;
  List<dynamic> _trips    = [];
  List<dynamic> _invoices = [];
  Map<String, dynamic> _tripStats = {};

  bool _loading     = true;
  bool _tripsLoading = false;
  bool _actionLoading = false;

  int _selectedMonth = DateTime.now().month;
  int _selectedYear  = DateTime.now().year;

  DateTime _dateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
DateTime _dateTo   = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
String? _statusFilter;

  late TabController _tabController;

  // Expandable sections
  final Map<String, bool> _expanded = {
    'org': true,
    'vehicles': true,
    'surcharges': false,
    'sla': false,
    'documents': false,
    'trips': true,
    'invoices': true,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([_loadCard(), _loadInvoices()]);
    setState(() => _loading = false);
  }

  Future<void> _pickDateRange() async {
  final picked = await showDialog<DateTimeRange>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AC.blue,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select Start Date',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AC.blue,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                  ),
                ),
                child: CalendarDatePicker(
                  initialDate: _dateFrom,
                  firstDate: DateTime(2024, 1, 1),
                  lastDate: DateTime(2027, 12, 31),
                  onDateChanged: (date) {
                    // Store start date and show second picker
                    showDialog<DateTime>(
                      context: ctx,
                      builder: (ctx2) => Dialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(
                                  color: AC.blue,
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.date_range, color: Colors.white, size: 20),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Select End Date',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                                      onPressed: () => Navigator.of(ctx2).pop(),
                                    ),
                                  ],
                                ),
                              ),
                              Flexible(
                                child: Theme(
                                  data: Theme.of(ctx2).copyWith(
                                    colorScheme: const ColorScheme.light(
                                      primary: AC.blue,
                                      onPrimary: Colors.white,
                                      surface: Colors.white,
                                    ),
                                  ),
                                  child: CalendarDatePicker(
                                    initialDate: date.add(const Duration(days: 1)),
                                    firstDate: date,
                                    lastDate: DateTime(2027, 12, 31),
                                    onDateChanged: (endDate) {
                                      Navigator.of(ctx2).pop(endDate);
                                      Navigator.of(ctx).pop(DateTimeRange(start: date, end: endDate));
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked != null) {
    setState(() {
      _dateFrom = picked.start;
      _dateTo   = picked.end;
    });
    await _loadTrips(_card!['domain']);
  }
}

  Future<void> _loadCard() async {
    try {
      print('📡 Loading rate card: ${widget.rateCardId}');
      print('📡 API URL: ${ApiService.base}/api/rate-cards/${widget.rateCardId}');
      
      final res = await ApiService.get(
          '/api/rate-cards/${widget.rateCardId}', token: widget.authToken);
      
      print('📡 Rate card response: ${res['success']}');
      
      if (res['success'] == true) {
        setState(() => _card = res['data']);
        print('✅ Rate card loaded successfully');
        // Load trips once we have the domain
        final domain = _card?['domain'];
        if (domain != null) await _loadTrips(domain);
      } else {
        print('❌ Rate card load failed: ${res['error']}');
        _snack(res['error'] ?? 'Failed to load rate card', error: true);
      }
    } catch (e) {
      print('❌ Rate card load exception: $e');
      _snack('Failed to load rate card: $e', error: true);
      // Don't set _card to null, keep it as is to prevent automatic pop
    }
  }

  Future<void> _loadTrips(String domain) async {
  setState(() => _tripsLoading = true);
  try {
    String pad(int n) => n.toString().padLeft(2, '0');
    final from        = '${_dateFrom.year}-${pad(_dateFrom.month)}-${pad(_dateFrom.day)}';
    final to          = '${_dateTo.year}-${pad(_dateTo.month)}-${pad(_dateTo.day)}';
    final statusParam = _statusFilter != null ? '&status=$_statusFilter' : '';
    final url         = '/api/billing/trips/$domain?dateFrom=$from&dateTo=$to$statusParam';
    final res         = await ApiService.get(url, token: widget.authToken);
    if (res['success'] == true) {
      setState(() {
        _trips     = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _tripStats = Map<String, dynamic>.from(res['stats'] ?? {});
      });
    }
  } catch (_) {}
  setState(() => _tripsLoading = false);
}

  Future<void> _loadInvoices() async {
    if (_card == null) return;
    try {
      final domain = _card!['domain'];
      final res = await ApiService.get(
          '/api/billing/invoices?domain=$domain', token: widget.authToken);
      if (res['success'] == true) setState(() => _invoices = res['data'] ?? []);
    } catch (_) {}
  }

  Future<void> _activateCard() async {
    setState(() => _actionLoading = true);
    try {
      final res = await ApiService.post(
          '/api/rate-cards/${widget.rateCardId}/activate', {},
          token: widget.authToken);
      if (res['success'] == true) {
        _snack('Rate card activated ✓', error: false);
        await _loadCard();
      } else {
        _snack(res['error'] ?? 'Failed to activate', error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
    setState(() => _actionLoading = false);
  }

  Future<void> _suspendCard() async {
    final confirm = await _showConfirmDialog(
        'Suspend Rate Card?',
        'Billing for ${_card?['organizationName']} will stop. You can re-activate later.');
    if (!confirm) return;

    setState(() => _actionLoading = true);
    try {
      final res = await ApiService.post(
          '/api/rate-cards/${widget.rateCardId}/suspend', {},
          token: widget.authToken);
      if (res['success'] == true) {
        _snack('Rate card suspended', error: false);
        await _loadCard();
      } else {
        _snack(res['error'] ?? 'Failed', error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
    setState(() => _actionLoading = false);
  }

  Future<void> _generateInvoice() async {
    final confirm = await _showConfirmDialog(
        'Generate Invoice?',
        'Generate billing invoice for ${_card?['organizationName']} for '
        '${DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth))}?');
    if (!confirm) return;

    setState(() => _actionLoading = true);
    try {
      final res = await ApiService.post('/api/billing/generate-invoice', {
        'domain': _card!['domain'],
        'month':  _selectedMonth,
        'year':   _selectedYear,
      }, token: widget.authToken);

      if (res['success'] == true) {
        final inv = res['data'];
        _snack('Invoice ${inv['invoiceNumber']} created — pending Finance approval ✓',
            error: false);
        await _loadInvoices();
        _tabController.animateTo(2);
      } else {
        _snack(res['error'] ?? 'Failed to generate invoice', error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
    setState(() => _actionLoading = false);
  }

  Future<void> _approveInvoice(String invoiceId, String invoiceNumber) async {
    final confirm = await _showConfirmDialog(
        'Approve Invoice?',
        'Approve $invoiceNumber and send to organisation?');
    if (!confirm) return;

    setState(() => _actionLoading = true);
    try {
      // Approve
      final approveRes = await ApiService.post(
          '/api/billing/invoices/$invoiceId/approve',
          {'approvedBy': 'finance_team'},
          token: widget.authToken);

      if (approveRes['success'] == true) {
        // Auto-send
        final sendRes = await ApiService.post(
            '/api/billing/invoices/$invoiceId/send', {},
            token: widget.authToken);

        if (sendRes['success'] == true) {
          _snack('$invoiceNumber approved and sent to ${_card?['billingEmail']} ✓',
              error: false);
        } else {
          _snack('Approved but email failed: ${sendRes['error']}', error: true);
        }
        await _loadInvoices();
      } else {
        _snack(approveRes['error'] ?? 'Approval failed', error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
    setState(() => _actionLoading = false);
  }

  Future<void> _uploadDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true, // ✅ CRITICAL: Ensures file.bytes is available on web
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    _snack('Uploading ${file.name}...', error: false);

    try {
      final uri = Uri.parse(
          '${ApiService.base}/api/rate-cards/${widget.rateCardId}/upload-document');
      final request = http.MultipartRequest('POST', uri);
      if (widget.authToken != null) {
        request.headers['Authorization'] = 'Bearer ${widget.authToken}';
      }
      
      // ✅ FIX: Use bytes for web compatibility instead of path
      if (file.bytes != null) {
        // Web platform: use bytes
        request.files.add(http.MultipartFile.fromBytes(
          'document',
          file.bytes!,
          filename: file.name,
        ));
      } else if (file.path != null) {
        // Mobile/Desktop platform: use path
        request.files.add(await http.MultipartFile.fromPath('document', file.path!));
      } else {
        throw Exception('Unable to read file');
      }
      
      final response = await request.send();
      final body     = await response.stream.bytesToString();
      final parsed   = jsonDecode(body);

      if (parsed['success'] == true) {
        _snack('${file.name} uploaded ✓', error: false);
        await _loadCard();
      } else {
        _snack(parsed['error'] ?? 'Upload failed', error: true);
      }
    } catch (e) {
      _snack('Upload error: $e', error: true);
    }
  }

  // ── Navigate to Edit Screen ───────────────────────────────────────
  Future<void> _navigateToEdit() async {
    if (_card == null) return;

    // Push CreateRateCardScreen in EDIT mode, passing the full card data
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => CreateRateCardScreen(
          authToken:    widget.authToken,
          existingCard: _card, // triggers edit mode inside CreateRateCardScreen
        ),
      ),
    );

    // result is {'updated': true, 'data': updatedCard} when saved
    if (result != null && result['updated'] == true) {
      final updatedCard = result['data'] as Map<String, dynamic>?;
      if (updatedCard != null) {
        setState(() => _card = updatedCard);
        // Also reload trips/invoices in case domain or dates changed
        final domain = updatedCard['domain'];
        if (domain != null) await _loadTrips(domain);
        await _loadInvoices();
        _snack('Rate card updated ✓', error: false);
      } else {
        // Fallback: full reload from API
        await _loadAll();
        _snack('Rate card updated ✓', error: false);
      }
    }
  }

  void _snack(String msg, {required bool error}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AC.red : AC.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<bool> _showConfirmDialog(String title, String body) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text(body, style: const TextStyle(color: AC.textMid)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: AC.textMid))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AC.navy, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;
  }

  // Helper method for dropdown decoration
  InputDecoration _dropDec() {
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AC.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AC.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AC.blue, width: 2),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final r = _R(constraints.maxWidth);

      if (_loading) {
        return Scaffold(
          backgroundColor: AC.bg,
          appBar: AppBar(backgroundColor: AC.navyDark, foregroundColor: Colors.white,
              title: const Text('Rate Card Detail')),
          body: const Center(child: CircularProgressIndicator(color: AC.blue)),
        );
      }

      if (_card == null) {
        return Scaffold(
          backgroundColor: AC.bg,
          appBar: AppBar(backgroundColor: AC.navyDark, foregroundColor: Colors.white,
              title: const Text('Rate Card Detail')),
          body: const Center(child: Text('Rate card not found', style: TextStyle(color: AC.textMid))),
        );
      }

      return Scaffold(
        backgroundColor: AC.bg,
        body: NestedScrollView(
          headerSliverBuilder: (_, __) => [_buildSliverHeader(r)],
          body: Column(
            children: [
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDetailsTab(r),
                    _buildTripsTab(r),
                    _buildInvoicesTab(r),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  SliverAppBar _buildSliverHeader(_R r) {
    final status = _card!['status'] ?? 'DRAFT';
    final org    = _card!['organizationName'] ?? '—';
    final domain = _card!['domain'] ?? '—';
    final rcId   = _card!['rateCardId'] ?? '—';
    final hPad   = r.isMobile ? 20.0 : 40.0;
    final contractStart = fmtDate(_card!['contractStartDate']);
    final contractEnd = fmtDate(_card!['contractEndDate']);

    return SliverAppBar(
      expandedHeight: r.isMobile ? 180 : 140,
      pinned: true,
      backgroundColor: AC.navyDark,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Back to Rate Cards',
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A1628), Color(0xFF1A2744), Color(0xFF1E3A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: r.maxW),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 56, hPad, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ NEW LAYOUT: Left side - Company name, status, rate card number
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left side
                          Expanded(
                            flex: r.isMobile ? 1 : 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Abra fleet', 
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: r.isMobile ? 16 : 20,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3
                                      )
                                    ),
                                    const SizedBox(width: 12),
                                    _statusBadge(status),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(rcId, 
                                  style: const TextStyle(
                                    color: Colors.white70, 
                                    fontSize: 13, 
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5
                                  )
                                ),
                              ],
                            ),
                          ),
                          
                          // Right side - Single responsive row with all controls
                          if (!r.isMobile) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: _buildResponsiveControlsRow(r, status, domain, contractStart, contractEnd),
                            ),
                          ],
                        ],
                      ),
                      
                      // Mobile: Show controls below
                      if (r.isMobile) ...[
                        const SizedBox(height: 12),
                        _buildResponsiveControlsRow(r, status, domain, contractStart, contractEnd),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ NEW: Responsive controls row
  Widget _buildResponsiveControlsRow(_R r, String status, String domain, String contractStart, String contractEnd) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: r.isMobile ? WrapAlignment.start : WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Date Range
        _compactInfoChip(Icons.calendar_today_outlined, '$contractStart → $contractEnd'),
        
        // Domain
        _compactInfoChip(Icons.language, domain),
        
        // Action buttons
        if (!_actionLoading) ...[
          if (status == 'DRAFT')
            _compactActionBtn('Activate', Icons.check_circle_outline, AC.green, _activateCard),
          if (status == 'ACTIVE')
            _compactActionBtn('Suspend', Icons.pause_circle_outline, AC.amber, _suspendCard),
          if (status == 'SUSPENDED')
            _compactActionBtn('Re-activate', Icons.play_circle_outline, AC.green, _activateCard),
          _compactActionBtn('Edit', Icons.edit_outlined, Colors.white70, _navigateToEdit),
        ] else
          const SizedBox(
            width: 20, 
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
          ),
      ],
    );
  }

  // ✅ NEW: Compact info chip for AppBar
  Widget _compactInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 12),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ✅ NEW: Compact action button for AppBar
  Widget _compactActionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: statusBg(status),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: statusColor(status).withOpacity(0.4)),
    ),
    child: Text(status.replaceAll('_', ' '),
        style: TextStyle(color: statusColor(status), fontSize: 11,
            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
  );

  Widget _statusPill(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _tripStatusBg(status),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _tripStatusColor(status).withOpacity(0.3)),
    ),
    child: Text(status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: _tripStatusColor(status), fontSize: 10,
            fontWeight: FontWeight.w700)),
  );

Widget _buildStatusFilters(_R r) {
  final filters = [
    {'label': 'All',       'value': null,          'icon': Icons.list_alt_outlined},
    {'label': 'Assigned',  'value': 'assigned',    'icon': Icons.assignment_outlined},
    {'label': 'Ongoing',   'value': 'in_progress', 'icon': Icons.directions_car},
    {'label': 'Completed', 'value': 'completed',   'icon': Icons.check_circle_outline},
    {'label': 'Cancelled', 'value': 'cancelled',   'icon': Icons.cancel_outlined},
  ];
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: filters.map((f) {
        final val   = f['value'] as String?;
        final label = f['label'] as String;
        final icon  = f['icon']  as IconData;
        final active = _statusFilter == val;
        final color  = _filterColor(val);
        return GestureDetector(
          onTap: () {
            setState(() => _statusFilter = val);
            _loadTrips(_card!['domain']);
          },
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color:        active ? color : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(
                  color: active ? color : AC.border, width: active ? 1.5 : 1),
              boxShadow: active
                  ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 6)]
                  : [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: active ? Colors.white : AC.textMid),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w700,
                      color:      active ? Colors.white : AC.textMid)),
            ]),
          ),
        );
      }).toList(),
    ),
  );
}



  Color _filterColor(String? status) {
  switch (status) {
    case 'completed':   return AC.green;
    case 'in_progress': return AC.blue;
    case 'assigned':    return AC.amber;
    case 'cancelled':   return AC.red;
    default:            return AC.navy;
  }
}

Widget _buildTripsTable(_R r) {
  const cols = [
    _ColDef('#',            40),
    _ColDef('Trip Number',  200),
    _ColDef('Date',         120),
    _ColDef('Vehicle',      105),
    _ColDef('Driver',       135),
    _ColDef('Status',       115),
    _ColDef('Pax',           55),
    _ColDef('Actual KM',     95),
    _ColDef('Billed KM',     95),
    _ColDef('Base Amt',     115),
    _ColDef('Surcharges',   110),
    _ColDef('Total',        120),
    _ColDef('Billing',      115),
  ];
  final totalWidth = cols.fold(0.0, (s, c) => s + c.width) + 32.0;

  final Map<String, List<Map<String, dynamic>>> grouped = {};
  for (final t in _trips) {
    final raw = t['scheduledDate']?.toString() ?? '';
    String label = '—';
    if (raw.isNotEmpty) {
      try { label = DateFormat('dd MMM yyyy').format(DateTime.parse(raw)); }
      catch (_) { label = raw; }
    } else {
      try {
        label = DateFormat('dd MMM yyyy')
            .format(DateTime.parse(t['tripDate']?.toString() ?? ''));
      } catch (_) {}
    }
    grouped.putIfAbsent(label, () => []).add(t);
  }

  final sortedKeys = grouped.keys.toList()
    ..sort((a, b) {
      try {
        return DateFormat('dd MMM yyyy').parse(b)
            .compareTo(DateFormat('dd MMM yyyy').parse(a));
      } catch (_) { return 0; }
    });

  return Scrollbar(
    thumbVisibility: true,
    trackVisibility: true,
    child: SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Scrollbar(
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (n) => n.depth == 1,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tableHeader(cols),
                ...sortedKeys.map((dateKey) {
                  final rows     = grouped[dateKey]!;
                  final dayTotal = rows.fold(0.0, (s, t) =>
                      s + ((t['subtotalBeforeTax'] as num?) ?? 0).toDouble());
                  final dayKm   = rows.fold(0.0, (s, t) =>
                      s + ((t['actualKm'] as num?) ?? 0).toDouble());
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: totalWidth,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        color: AC.navyDark,
                        child: Row(children: [
                          const Icon(Icons.calendar_today_outlined,
                              color: Colors.white54, size: 12),
                          const SizedBox(width: 8),
                          Text(dateKey,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w800,
                                  fontSize: 12, letterSpacing: 0.4)),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${rows.length} trip${rows.length > 1 ? 's' : ''}',
                                style: const TextStyle(color: Colors.white60, fontSize: 11)),
                          ),
                          const SizedBox(width: 10),
                          Text('${fmtNum(dayKm)} km',
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          const Spacer(),
                          Text(fmtCurrency(dayTotal),
                              style: const TextStyle(
                                  color: AC.green, fontWeight: FontWeight.w800, fontSize: 12)),
                        ]),
                      ),
                      ...rows.asMap().entries.map((e) => _tableRow(e.value, e.key, cols)),
                    ],
                  );
                }).toList(),
                _tableFooter(cols, totalWidth),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _tableHeader(List<_ColDef> cols) => Container(
  color: AC.navy,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
  child: Row(
    children: cols.map((c) => SizedBox(
      width: c.width,
      child: c.label == 'Date' 
        ? Center(child: Text(c.label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13,
                fontWeight: FontWeight.w700, letterSpacing: 0.4)))
        : Text(c.label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13,
                fontWeight: FontWeight.w700, letterSpacing: 0.4)),
    )).toList(),
  ),
);

Widget _tableRow(Map<String, dynamic> t, int rowIndex, List<_ColDef> cols) {
  final even       = rowIndex.isEven;
  final tripNumber = t['tripNumber']?.toString()
      ?? t['tripId']?.toString().substring(0, 8) ?? '—';
  final vehicle    = kVehicleLabels[t['vehicleType']] ?? t['vehicleType']?.toString() ?? '—';
  final driver     = (t['driverName']?.toString().isNotEmpty == true)
      ? t['driverName'].toString() : '—';
  final status     = t['status']?.toString()        ?? '';
  final billing    = t['billingStatus']?.toString() ?? 'NOT_CALCULATED';
  final pax        = (t['customerCount'] as num?)?.toInt()        ?? 0;
  final actualKm   = (t['actualKm']         as num?)?.toDouble()  ?? 0.0;
  final billedKm   = (t['billedKm']          as num?)?.toDouble() ?? 0.0;
  final baseAmt    = (t['baseAmount']        as num?)?.toDouble() ?? 0.0;
  final surcharges = (t['totalSurcharges']   as num?)?.toDouble() ?? 0.0;
  final total      = (t['subtotalBeforeTax'] as num?)?.toDouble() ?? 0.0;

  String displayDate = '—';
  final rawSched = t['scheduledDate']?.toString() ?? '';
  if (rawSched.isNotEmpty) {
    try { displayDate = DateFormat('dd MMM yy').format(DateTime.parse(rawSched)); }
    catch (_) { displayDate = rawSched; }
  } else {
    try { displayDate = DateFormat('dd MMM yy')
        .format(DateTime.parse(t['tripDate']?.toString() ?? '')); }
    catch (_) {}
  }

  return Container(
    color: even ? Colors.white : const Color(0xFFF8FAFD),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AC.border.withOpacity(0.5)))),
    child: Row(children: [
      SizedBox(width: cols[0].width,
          child: Text('${rowIndex + 1}',
              style: const TextStyle(fontSize: 11, color: AC.textLight))),
      SizedBox(width: cols[1].width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tripNumber,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12, color: AC.textDark),
                overflow: TextOverflow.ellipsis),
            if ((t['tripType'] ?? '').toString().isNotEmpty)
              Text((t['tripType'] as String).toUpperCase(),
                  style: const TextStyle(fontSize: 9, color: AC.textLight, letterSpacing: 0.4)),
          ])),
      SizedBox(width: cols[2].width,
          child: Center(child: Text(displayDate,
              style: const TextStyle(fontSize: 14, color: AC.textMid, fontWeight: FontWeight.w600)))),
      SizedBox(width: cols[3].width,
          child: Text(vehicle,
              style: const TextStyle(fontSize: 11, color: AC.textMid, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis)),
      SizedBox(width: cols[4].width,
          child: Text(driver,
              style: const TextStyle(fontSize: 11, color: AC.textMid),
              overflow: TextOverflow.ellipsis)),
      SizedBox(width: cols[5].width, child: _statusPill(status)),
      SizedBox(width: cols[6].width,
          child: pax > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: AC.blueLight, borderRadius: BorderRadius.circular(10)),
                  child: Text('$pax',
                      style: const TextStyle(
                          fontSize: 10, color: AC.blue, fontWeight: FontWeight.w700)))
              : const Text('—', style: TextStyle(color: AC.textLight, fontSize: 12))),
      SizedBox(width: cols[7].width,
          child: Text(actualKm > 0 ? '${fmtNum(actualKm)} km' : '—',
              style: const TextStyle(fontSize: 12, color: AC.textDark, fontWeight: FontWeight.w600))),
      SizedBox(width: cols[8].width,
          child: Text(billedKm > 0 ? '${fmtNum(billedKm)} km' : '—',
              style: const TextStyle(fontSize: 11, color: AC.textMid))),
      SizedBox(width: cols[9].width,
          child: Text(fmtCurrency(baseAmt),
              style: TextStyle(fontSize: 12,
                  color: baseAmt > 0 ? AC.textDark : AC.textLight,
                  fontWeight: FontWeight.w600))),
      SizedBox(width: cols[10].width,
          child: Text(surcharges > 0 ? fmtCurrency(surcharges) : '—',
              style: TextStyle(fontSize: 11,
                  color: surcharges > 0 ? AC.amber : AC.textLight))),
      SizedBox(width: cols[11].width,
          child: Text(fmtCurrency(total),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                  color: total > 0 ? AC.navyDark : AC.textLight))),
      SizedBox(width: cols[12].width, child: _billingPill(billing)),
    ]),
  );
}



Widget _tableFooter(List<_ColDef> cols, double totalWidth) => Container(
  width: totalWidth,
  color: AC.navyDark,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  child: Row(children: [
    SizedBox(width: cols[0].width),
    SizedBox(width: cols[1].width,
        child: Text('TOTAL  (${_trips.length} trips)',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))),
    SizedBox(width: cols[2].width),
    SizedBox(width: cols[3].width),
    SizedBox(width: cols[4].width),
    SizedBox(width: cols[5].width),
    SizedBox(width: cols[6].width),
    SizedBox(width: cols[7].width,
        child: Text('${fmtNum(_tripStats['totalKm'] ?? 0)} km',
            style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12))),
    SizedBox(width: cols[8].width),
    SizedBox(width: cols[9].width,
        child: Text(fmtCurrency(_tripStats['totalBaseAmount'] ?? 0),
            style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12))),
    SizedBox(width: cols[10].width,
        child: Text(fmtCurrency(_tripStats['totalSurcharges'] ?? 0),
            style: TextStyle(
                color: AC.amberLight.withOpacity(0.85),
                fontWeight: FontWeight.w700, fontSize: 12))),
    SizedBox(width: cols[11].width,
        child: Text(fmtCurrency(_tripStats['totalBilledAmount'] ?? 0),
            style: const TextStyle(
                color: AC.green, fontWeight: FontWeight.w900, fontSize: 15))),
    SizedBox(width: cols[12].width),
  ]),
);

Widget _billingPill(String status) {
  Color bg, fg; String label;
  switch (status) {
    case 'CALCULATED':  bg = AC.greenLight;  fg = AC.greenDark; label = 'Calculated'; break;
    case 'ON_THE_FLY':  bg = AC.blueLight;   fg = AC.blue;      label = 'Live Calc';  break;
    case 'INVOICED':    bg = AC.purpleLight; fg = AC.purple;    label = 'Invoiced';   break;
    case 'PAID':        bg = AC.greenLight;  fg = AC.greenDark; label = 'Paid';       break;
    default:            bg = AC.bg;          fg = AC.textLight; label = 'Pending';
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: fg.withOpacity(0.2)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
  );
}

  // ── Tab Bar ───────────────────────────────────────────────────────
  Widget _buildTabBar() => Container(
    color: AC.navy,
    child: TabBar(
      controller: _tabController,
      indicatorColor: AC.blue,
      indicatorWeight: 3,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white54,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      tabs: const [
        Tab(text: 'Details'),
        Tab(text: 'Trips'),
        Tab(text: 'Invoices'),
      ],
    ),
  );

  // ══════════════════════════════════════════════════════════════════
  // TAB 1 — DETAILS
  // ══════════════════════════════════════════════════════════════════

  Widget _buildDetailsTab(_R r) => RefreshIndicator(
    onRefresh: _loadAll,
    color: AC.blue,
    child: ListView(
      padding: EdgeInsets.fromLTRB(r.hPad, 16, r.hPad, 32),
      children: [
        Center(child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: r.maxW),
          child: Column(children: [
            _buildOrgSection(r),
            _buildVehicleRatesSection(r),
            _buildSurchargesSection(r),
            _buildSlaSection(r),
            _buildDocumentsSection(r),
          ]),
        )),
      ],
    ),
  );

  Widget _buildOrgSection(_R r) => _expandableSection(
    key: 'org',
    icon: Icons.business_outlined,
    title: 'Organisation & Contract',
    iconColor: AC.blue,
    child: r.isMobile
        ? Column(children: [
            _twoCol('Organisation',   _card!['organizationName']),
            _twoCol('Domain',         _card!['domain']),
            _twoCol('Billing Email',  _card!['billingEmail']),
            _twoCol('Contact Person', _card!['contactPersonName']),
            _twoCol('Contact Phone',  _card!['contactPersonPhone']),
            _twoCol('GST Number',     _card!['gstNumber']),
            _divider(),
            _twoCol('Contract Start', fmtDate(_card!['contractStartDate'])),
            _twoCol('Contract End',   fmtDate(_card!['contractEndDate'])),
            _twoCol('Billing Cycle',  _card!['billingCycle']),
            _twoCol('Payment Terms',  _card!['paymentTerms']),
            _twoCol('Credit Period',  '${_card!['creditPeriodDays'] ?? 30} days'),
            _divider(),
            _twoColHighlight('GST %', '${_card!['gstPercent'] ?? 5}%', AC.blue),
            _twoColHighlight('TDS %', '${_card!['tdsPercent'] ?? 1}%', AC.amber),
            _divider(),
            if (_card!['billingAddress'] != null)
              _twoCol('Address', [
                _card!['billingAddress']['street'],
                _card!['billingAddress']['city'],
                _card!['billingAddress']['state'],
                _card!['billingAddress']['pincode'],
              ].where((v) => v != null && v.toString().isNotEmpty).join(', ')),
            if (_card!['internalNotes'] != null &&
                _card!['internalNotes'].toString().isNotEmpty) ...[
              _divider(), _noteBlock(_card!['internalNotes']),
            ],
          ])
        : _infoGrid(r, [
            _InfoItem('Organisation',   _card!['organizationName']),
            _InfoItem('Domain',         _card!['domain']),
            _InfoItem('Billing Email',  _card!['billingEmail']),
            _InfoItem('Contact Person', _card!['contactPersonName']),
            _InfoItem('Contact Phone',  _card!['contactPersonPhone']),
            _InfoItem('GST Number',     _card!['gstNumber']),
            _InfoItem('Contract Start', fmtDate(_card!['contractStartDate'])),
            _InfoItem('Contract End',   fmtDate(_card!['contractEndDate'])),
            _InfoItem('Billing Cycle',  _card!['billingCycle']),
            _InfoItem('Payment Terms',  _card!['paymentTerms']),
            _InfoItem('Credit Period',  '${_card!['creditPeriodDays'] ?? 30} days'),
            _InfoItem('GST %',          '${_card!['gstPercent'] ?? 5}%', highlight: AC.blue),
            _InfoItem('TDS %',          '${_card!['tdsPercent'] ?? 1}%', highlight: AC.amber),
            if (_card!['billingAddress'] != null)
              _InfoItem('Address', [
                _card!['billingAddress']['street'],
                _card!['billingAddress']['city'],
                _card!['billingAddress']['state'],
                _card!['billingAddress']['pincode'],
              ].where((v) => v != null && v.toString().isNotEmpty).join(', ')),
          ]),
  );

  // ── Section: Vehicle Rate Matrix ──────────────────────────────────
  Widget _buildVehicleRatesSection(_R r) {
    final rates = _card!['vehicleRates'] as List? ?? [];
    return _expandableSection(
      key: 'vehicles',
      icon: Icons.directions_car_outlined,
      title: 'Vehicle Rate Matrix',
      badge: '${rates.length} vehicle types',
      iconColor: AC.purple,
      child: r.isMobile
          ? Column(children: rates.asMap().entries
              .map((e) => _vehicleRateCard(e.key, e.value)).toList())
          : Wrap(
              spacing: 12, runSpacing: 12,
              children: rates.asMap().entries.map((e) => SizedBox(
                width: r.isDesktop
                    ? (r.maxW - 2 * r.hPad - 24) / 3
                    : (r.maxW - 2 * r.hPad - 12) / 2,
                child: _vehicleRateCard(e.key, e.value),
              )).toList(),
            ),
    );
  }

  Widget _vehicleRateCard(int index, Map<String, dynamic> rate) {
    final vt    = rate['vehicleType']  ?? '';
    final model = rate['billingModel'] ?? '';
    final icon  = kBillingModelIcons[model] ?? Icons.payment;
    final active = rate['isActive'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: active ? AC.blueLight : AC.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? AC.blueBorder : AC.border),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: active ? AC.navy : AC.textMid,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(Icons.directions_car, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Text(kVehicleLabels[vt] ?? vt,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(kBillingModelLabels[model] ?? model,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),

          // Rate details
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              if (model == 'PER_KM') ...[
                _rateRow('Rate per KM',        fmtCurrency(rate['ratePerKm'])),
                _rateRow('Minimum KM / Trip',  fmtNum(rate['minimumKmPerTrip']) + ' km'),
              ],
              if (model == 'PER_TRIP_FIXED')
                _rateRow('Rate per Trip',       fmtCurrency(rate['ratePerTrip'])),
              if (model == 'DEDICATED_MONTHLY') ...[
                _rateRow('Monthly Rate',        fmtCurrency(rate['monthlyRate'])),
                _rateRow('Included KM / Month', fmtNum(rate['includedKmPerMonth']) + ' km'),
              ],
              if (model == 'HYBRID') ...[
                _rateRow('Monthly Base',        fmtCurrency(rate['hybridMonthlyBase'])),
                _rateRow('Included KM',         fmtNum(rate['hybridIncludedKm']) + ' km'),
                _rateRow('Excess Rate / KM',    fmtCurrency(rate['hybridExcessRatePerKm'])),
              ],
              if ((rate['minimumTripsPerMonth'] ?? 0) > 0)
                _rateRow('Min Trips / Month Guarantee',
                    '${rate['minimumTripsPerMonth']} trips', highlight: true),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _rateRow(String label, String value, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AC.textMid, fontWeight: FontWeight.w500)),
      const Spacer(),
      Container(
        padding: highlight ? const EdgeInsets.symmetric(horizontal: 10, vertical: 3) : EdgeInsets.zero,
        decoration: highlight ? BoxDecoration(
          color: AC.amberLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AC.amber.withOpacity(0.4)),
        ) : null,
        child: Text(value, style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: highlight ? AC.amber : AC.textDark)),
      ),
    ]),
  );

  // ── Section: Surcharges ───────────────────────────────────────────
  Widget _buildSurchargesSection(_R r) {
    final s = _card!['surchargeRules'] as Map<String, dynamic>? ?? {};
    final enabled = <Widget>[];

    if (s['nightShiftEnabled'] == true)
      enabled.add(_surchargeChip(Icons.nights_stay, 'Night Shift',
          '₹${s['nightSurchargePerTrip']} / trip (${s['nightStartHour']}:00 – ${s['nightEndHour']}:00)'));
    if (s['weekendEnabled'] == true)
      enabled.add(_surchargeChip(Icons.weekend, 'Weekend',
          '${s['weekendSurchargePercent']}% on base'));
    if (s['festivalEnabled'] == true)
      enabled.add(_surchargeChip(Icons.celebration, 'Festival',
          '${s['festivalSurchargePercent']}% on base'));
    if (s['waitingEnabled'] == true)
      enabled.add(_surchargeChip(Icons.timer, 'Waiting',
          '₹${s['waitingRatePerMinute']}/min after ${s['waitingFreeMinutes']}min free'));
    if ((s['tollType'] ?? 'NOT_APPLICABLE') != 'NOT_APPLICABLE')
      enabled.add(_surchargeChip(Icons.toll, 'Toll',
          s['tollType'] == 'ACTUALS' ? 'Actuals reimbursed' : '₹${s['tollFlatRatePerTrip']} flat'));
    if (s['escortEnabled'] == true)
      enabled.add(_surchargeChip(Icons.security, 'Escort',
          '₹${s['escortSurchargePerTrip']} / trip'));

    return _expandableSection(
      key: 'surcharges',
      icon: Icons.add_circle_outline,
      title: 'Surcharge Rules',
      badge: '${enabled.length} active',
      iconColor: AC.amber,
      child: enabled.isEmpty
          ? _emptyState('No surcharges configured', Icons.check_circle_outline)
          : Wrap(spacing: 10, runSpacing: 10, children: enabled),
    );
  }

  Widget _surchargeChip(IconData icon, String title, String subtitle) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AC.amberLight,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AC.amber.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AC.amber, size: 16),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AC.textDark)),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: AC.textMid)),
      ]),
    ]),
  );

  // ── Section: SLA ──────────────────────────────────────────────────
  Widget _buildSlaSection(_R r) {
    final s = _card!['slaTerms'] as Map<String, dynamic>? ?? {};
    return _expandableSection(
      key: 'sla',
      icon: Icons.verified_outlined,
      title: 'SLA Terms',
      iconColor: AC.green,
      child: r.isMobile
          ? Column(children: [
              _twoCol('On-Time Pickup Target',    '${s['onTimePickupPercent'] ?? 95}%'),
              _twoCol('L1 Escalation',            '${s['l1EscalationMinutes'] ?? 10} min delay'),
              _twoCol('L2 Escalation',            '${s['l2EscalationMinutes'] ?? 20} min delay'),
              _twoCol('L3 Escalation',            '${s['l3EscalationMinutes'] ?? 30} min delay'),
              _divider(),
              _twoColHighlight('Penalty / Breach', fmtCurrency(s['penaltyPerBreachAmount']), AC.red),
              _twoColHighlight('Max Penalty / Month', fmtCurrency(s['maxPenaltyPerMonth']), AC.red),
            ])
          : _infoGrid(r, [
              _InfoItem('On-Time Pickup Target',  '${s['onTimePickupPercent'] ?? 95}%'),
              _InfoItem('L1 Escalation',          '${s['l1EscalationMinutes'] ?? 10} min delay'),
              _InfoItem('L2 Escalation',          '${s['l2EscalationMinutes'] ?? 20} min delay'),
              _InfoItem('L3 Escalation',          '${s['l3EscalationMinutes'] ?? 30} min delay'),
              _InfoItem('Penalty / Breach', fmtCurrency(s['penaltyPerBreachAmount']), highlight: AC.red),
              _InfoItem('Max Penalty / Month', fmtCurrency(s['maxPenaltyPerMonth']), highlight: AC.red),
            ]),
    );
  }

  // ── Section: Documents ────────────────────────────────────────────
  Widget _buildDocumentsSection(_R r) {
    final docs = _card!['documents'] as List? ?? [];
    return _expandableSection(
      key: 'documents',
      icon: Icons.folder_outlined,
      title: 'Contract Documents',
      badge: '${docs.length} files',
      iconColor: AC.textMid,
      trailing: _smallBtn('+ Upload', AC.blue, _uploadDocument),
      child: Column(children: [
        if (docs.isEmpty) _emptyState('No documents uploaded yet', Icons.upload_file),
        ...docs.map((d) => _documentRow(d)),
      ]),
    );
  }

  // ── Responsive info grid (tablet/desktop) ─────────────────────────
  Widget _infoGrid(_R r, List<_InfoItem> items) {
    final cols = r.infoCols;
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += cols) {
      final rowItems = items.sublist(i, (i + cols > items.length) ? items.length : i + cols);
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rowItems.map((item) => Expanded(child: _infoCell(item))),
          // Pad empty cells if last row is short
          ...List.generate(cols - rowItems.length, (_) => const Expanded(child: SizedBox())),
        ],
      ));
      if (i + cols < items.length) rows.add(const SizedBox(height: 4));
    }
    return Column(children: rows);
  }

  Widget _infoCell(_InfoItem item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(item.label, style: const TextStyle(fontSize: 11, color: AC.textLight, fontWeight: FontWeight.w500)),
      const SizedBox(height: 3),
      item.highlight != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: item.highlight!.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: item.highlight!.withOpacity(0.3)),
              ),
              child: Text(item.value?.toString() ?? '—',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: item.highlight)),
            )
          : Text(item.value?.toString() ?? '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AC.textDark)),
    ]),
  );

  Widget _documentRow(Map<String, dynamic> doc) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AC.bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AC.border),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AC.blueLight, borderRadius: BorderRadius.circular(8)),
        child: Icon(
          (doc['filename'] ?? '').endsWith('.pdf')
              ? Icons.picture_as_pdf : Icons.image_outlined,
          color: AC.blue, size: 18,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(doc['filename'] ?? 'Document',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        if (doc['uploadedAt'] != null)
          Text('Uploaded ${fmtDate(doc['uploadedAt'])}',
              style: const TextStyle(fontSize: 11, color: AC.textLight)),
      ])),
      GestureDetector(
        onTap: () async {
          final url = '${ApiService.base}${doc['filepath']}';
          if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
        },
        child: const Icon(Icons.download_outlined, color: AC.blue, size: 20),
      ),
    ]),
  );

  // ══════════════════════════════════════════════════════════════════
  // TAB 2 — TRIPS
  // ══════════════════════════════════════════════════════════════════

  Widget _buildTripsTab(_R r) {
  return Column(
    children: [
      _buildDateRangeBar(r),
      _buildTripStats(),
      Expanded(
        child: _tripsLoading
            ? const Center(child: CircularProgressIndicator(color: AC.blue))
            : _trips.isEmpty
                ? _emptyStateCenter(
                    'No trips found for this period',
                    Icons.directions_car_outlined)
                : RefreshIndicator(
                    onRefresh: () => _loadTrips(_card!['domain']),
                    color: AC.blue,
                    child: _buildTripsTable(r),
                  ),
      ),
    ],
  );
}

 Widget _buildMonthSelector(_R r) => _buildDateRangeBar(r);

  Widget _buildTripStats() {
    if (_tripStats.isEmpty) return const SizedBox();
    return Container(
      color: AC.navyDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        _statChip('Trips',       '${_tripStats['totalTrips'] ?? 0}',            Colors.white),
        _statChip('Billed KM',   '${fmtNum(_tripStats['totalKm'])} km',         Colors.white70),
        _statChip('Base Amt',    fmtCurrency(_tripStats['totalBaseAmount']),     AC.blueLight.withOpacity(0.9)),
        _statChip('Surcharges',  fmtCurrency(_tripStats['totalSurcharges']),     AC.amberLight.withOpacity(0.9)),
        _statChip('Total',       fmtCurrency(_tripStats['totalBilledAmount']),   AC.green),
      ]),
    );
  }

  Widget _statChip(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
    ]),
  );

 // ============================================================================
// FILE: rate_card_detail_screen.dart
// STEP 1: Copy everything below and use it as your FIND text
// ============================================================================

 // ============================================================================
// FILE: rate_card_detail_screen.dart
// STEP 2: Copy everything below and use it as your REPLACE text
// ============================================================================

Widget _buildDateRangeBar(_R r) => Container(
  padding: EdgeInsets.symmetric(horizontal: r.hPad, vertical: 12),
  color: AC.card,
  child: r.isMobile
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('Period:',
                style: TextStyle(fontWeight: FontWeight.w700, color: AC.textMid, fontSize: 15)),
            const SizedBox(width: 12),
            Expanded(child: _dateRangeTap()),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildStatusFilters(r)),
            const SizedBox(width: 8),
            // ✅ NEW: Refresh button
            IconButton(
              onPressed: () => _loadTrips(_card!['domain']),
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Refresh Trips',
              style: IconButton.styleFrom(
                backgroundColor: AC.blueLight,
                foregroundColor: AC.blue,
                padding: const EdgeInsets.all(11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _card!['status'] == 'ACTIVE' ? _generateInvoice : null,
              icon: const Icon(Icons.receipt_long, size: 16),
              label: const Text('Invoice',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AC.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ]),
        ])
      : Row(children: [
          const Text('Period:',
              style: TextStyle(fontWeight: FontWeight.w700, color: AC.textMid, fontSize: 15)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _dateRangeTap()),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: _buildStatusFilters(r)),
          const SizedBox(width: 12),
          // ✅ NEW: Refresh button
          IconButton(
            onPressed: () => _loadTrips(_card!['domain']),
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Trips',
            style: IconButton.styleFrom(
              backgroundColor: AC.blueLight,
              foregroundColor: AC.blue,
              padding: const EdgeInsets.all(11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _card!['status'] == 'ACTIVE' ? _generateInvoice : null,
            icon: const Icon(Icons.receipt_long, size: 16),
            label: const Text('Invoice',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AC.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ]),
);

Widget _dateRangeTap() => GestureDetector(
  onTap: () async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2027, 12, 31),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AC.blue,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AC.textDark,
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      await _loadTrips(_card!['domain']);
    }
  },
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: AC.blueLight,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AC.blueBorder),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.date_range_outlined, color: AC.blue, size: 18),
      const SizedBox(width: 8),
      Text(
        '${DateFormat('dd MMM yyyy').format(_dateFrom)}   →   '
        '${DateFormat('dd MMM yyyy').format(_dateTo)}',
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: AC.blue),
      ),
      const SizedBox(width: 8),
      const Icon(Icons.keyboard_arrow_down, color: AC.blue, size: 18),
    ]),
  ),
);



  Widget _tripBillingCard(Map<String, dynamic> t, _R r) {
    final isNight   = t['isNightTrip']   == true;
    final isWeekend = t['isWeekend']     == true;
    final isFest    = t['isFestival']    == true;
    final isEscort  = t['isEscortTrip']  == true;
    final hasSurcharges = (t['totalSurcharges'] ?? 0) > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AC.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AC.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Row 1: Trip Number + Date + Pax badge + Amount
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                t['tripNumber']?.toString() ?? t['tripId']?.toString().substring(0, 8) ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AC.textDark),
                overflow: TextOverflow.ellipsis,
              ),
              Row(children: [
                Text(fmtDate(t['tripDate']),
                    style: const TextStyle(fontSize: 11, color: AC.textLight)),
                if ((t['customerCount'] ?? 0) > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AC.blueLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${t['customerCount']} pax',
                        style: const TextStyle(fontSize: 9, color: AC.blue, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtCurrency(t['subtotalBeforeTax']),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AC.navyDark)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusBg(t['status']),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text((t['status'] ?? '').replaceAll('_', ' '),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: statusColor(t['status']))),
              ),
            ]),
          ]),

          const SizedBox(height: 10),

          // Row 2: Vehicle + Route
          Row(children: [
            _infoChip(Icons.directions_car_outlined, kVehicleLabels[t['vehicleType']] ?? t['vehicleType'] ?? '—'),
            const SizedBox(width: 8),
            if ((t['billingModel'] ?? '') == 'PER_KM')
              _infoChip(Icons.speed, '${fmtNum(t['actualKm'])} km (billed ${fmtNum(t['billedKm'])} km)'),
            if ((t['billingModel'] ?? '') == 'PER_TRIP_FIXED')
              _infoChip(Icons.confirmation_number_outlined, 'Fixed trip'),
          ]),

          // Route info
          if ((t['pickupZone'] ?? '').isNotEmpty || (t['dropZone'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.my_location, size: 12, color: AC.green),
              const SizedBox(width: 4),
              Expanded(child: Text('${t['pickupZone'] ?? ''} → ${t['dropZone'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: AC.textMid),
                  overflow: TextOverflow.ellipsis)),
            ]),
          ],

          // Flags
          if (isNight || isWeekend || isFest || isEscort) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              if (isNight)   _flagBadge('🌙 Night',   AC.navy),
              if (isWeekend) _flagBadge('📅 Weekend', AC.purple),
              if (isFest)    _flagBadge('🎉 Festival',AC.amber),
              if (isEscort)  _flagBadge('🛡️ Escort',  AC.green),
            ]),
          ],

          // Billing breakdown
          if (hasSurcharges) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AC.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                _billRow('Base Amount',         t['baseAmount']),
                if ((t['nightSurcharge']    ?? 0) > 0) _billRow('Night Surcharge',     t['nightSurcharge']),
                if ((t['weekendSurcharge']  ?? 0) > 0) _billRow('Weekend Surcharge',   t['weekendSurcharge']),
                if ((t['festivalSurcharge'] ?? 0) > 0) _billRow('Festival Surcharge',  t['festivalSurcharge']),
                if ((t['waitingSurcharge']  ?? 0) > 0) _billRow('Waiting Charges',     t['waitingSurcharge']),
                if ((t['tollSurcharge']     ?? 0) > 0) _billRow('Toll',                t['tollSurcharge']),
                if ((t['escortSurcharge']   ?? 0) > 0) _billRow('Escort',              t['escortSurcharge']),
                const Divider(height: 10, color: AC.border),
                _billRow('Total', t['subtotalBeforeTax'], bold: true, color: AC.navy),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AC.blueLight, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AC.blueBorder),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: AC.blue),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: AC.blueMid, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _flagBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _billRow(String label, dynamic amount, {bool bold = false, Color color = AC.textDark}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label, style: TextStyle(fontSize: 12, color: bold ? color : AC.textMid,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          const Spacer(),
          Text(fmtCurrency(amount), style: TextStyle(
              fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
        ]),
      );

  // ══════════════════════════════════════════════════════════════════
  // TAB 3 — INVOICES
  // ══════════════════════════════════════════════════════════════════

  Widget _buildInvoicesTab(_R r) => _invoices.isEmpty
      ? _emptyStateCenter('No invoices generated yet.\nGenerate from the Trips tab.', Icons.receipt_long_outlined)
      : RefreshIndicator(
          onRefresh: _loadInvoices,
          color: AC.blue,
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(r.hPad, 16, r.hPad, 32),
            itemCount: _invoices.length,
            itemBuilder: (_, i) => Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: r.maxW),
                child: _invoiceCard(_invoices[i]),
              ),
            ),
          ),
        );

  Widget _invoiceCard(Map<String, dynamic> inv) {
    final status      = inv['status'] ?? 'DRAFT';
    final isPending   = status == 'PENDING_FINANCE_APPROVAL';
    final isApproved  = status == 'APPROVED';
    final canApprove  = isPending || isApproved;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AC.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending ? AC.amber.withOpacity(0.5) : AC.border,
          width: isPending ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isPending ? AC.amberLight : AC.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Icon(Icons.receipt_long, color: isPending ? AC.amber : AC.textMid, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inv['invoiceNumber'] ?? '—',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                      color: isPending ? AC.amber : AC.textDark)),
              Text(inv['billingPeriodLabel'] ?? '—',
                  style: const TextStyle(fontSize: 12, color: AC.textMid)),
            ])),
            _statusBadge(status),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // Stats row
            Row(children: [
              _invStat('Total Amount',   fmtCurrency(inv['totalAmount']), AC.navy),
              _invStat('Subtotal',       fmtCurrency(inv['subtotal']),    AC.textMid),
              _invStat('Trips',          '${inv['completedTrips'] ?? 0}', AC.textMid),
              _invStat('KM',             '${fmtNum(inv['totalKm'])} km',  AC.textMid),
            ]),

            const SizedBox(height: 10),

            // Tax row
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AC.bg, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                _taxChip('GST ${inv['gstPercent'] ?? 5}%', fmtCurrency(inv['gstAmount']), AC.blue),
                const SizedBox(width: 8),
                _taxChip('CGST', fmtCurrency(inv['cgst']), AC.blue),
                const SizedBox(width: 8),
                _taxChip('SGST', fmtCurrency(inv['sgst']), AC.blue),
                const SizedBox(width: 8),
                _taxChip('TDS ${inv['tdsPercent'] ?? 1}%', '-${fmtCurrency(inv['tdsAmount'])}', AC.red),
              ]),
            ),

            // Finance approval info
            if (inv['financeApprovedBy'] != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AC.greenLight, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.verified, color: AC.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Approved by ${inv['financeApprovedBy']} on ${fmtDate(inv['financeApprovedAt'])}',
                    style: const TextStyle(fontSize: 12, color: AC.greenDark, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ],

            if (inv['sentToOrgAt'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AC.blueLight, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.email_outlined, color: AC.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Sent to ${inv['sentToOrgEmail']} on ${fmtDate(inv['sentToOrgAt'])}',
                    style: const TextStyle(fontSize: 12, color: AC.blueMid, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ],

            // Pending warning
            if (isPending) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AC.amberLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AC.amber.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.hourglass_top, color: AC.amber, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(
                    'Waiting for Finance team approval before sending to organisation',
                    style: TextStyle(fontSize: 12, color: AC.amber, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(children: [
              // Download PDF
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = '${ApiService.base}/api/billing/invoices/${inv['_id']}/pdf';
                    if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
                  },
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AC.blueMid,
                    side: const BorderSide(color: AC.border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              if (canApprove) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _actionLoading
                        ? null
                        : () => _approveInvoice(inv['_id'], inv['invoiceNumber']),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      isPending ? 'Approve & Send' : 'Send Again',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AC.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _invStat(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color)),
      Text(label, style: const TextStyle(fontSize: 9, color: AC.textLight)),
    ]),
  );

  Widget _taxChip(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(label, style: const TextStyle(fontSize: 9, color: AC.textLight)),
      Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    ]),
  );

  // ══════════════════════════════════════════════════════════════════
  // REUSABLE WIDGETS
  // ══════════════════════════════════════════════════════════════════

  Widget _expandableSection({
    required String key,
    required IconData icon,
    required String title,
    required Widget child,
    String? badge,
    Color iconColor = AC.blue,
    Widget? trailing,
  }) {
    final open = _expanded[key] ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AC.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AC.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _expanded[key] = !open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AC.bg,
              borderRadius: open
                  ? const BorderRadius.vertical(top: Radius.circular(14))
                  : BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      fontSize: 14, color: AC.textDark))),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(badge, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: iconColor)),
                ),
                const SizedBox(width: 8),
              ],
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: AC.textLight, size: 20),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: child,
          ),
      ]),
    );
  }

  Widget _twoCol(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 130,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AC.textMid,
              fontWeight: FontWeight.w500))),
      Expanded(child: Text(value?.toString() ?? '—',
          style: const TextStyle(fontSize: 12, color: AC.textDark, fontWeight: FontWeight.w700))),
    ]),
  );

  Widget _twoColHighlight(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      SizedBox(width: 130,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AC.textMid,
              fontWeight: FontWeight.w500))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(value, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      ),
    ]),
  );

  Widget _divider() => const Divider(color: AC.border, height: 16);

  Widget _noteBlock(String note) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AC.amberLight,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AC.amber.withOpacity(0.3)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.note_outlined, color: AC.amber, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(note,
          style: const TextStyle(fontSize: 12, color: AC.textDark, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _emptyState(String msg, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: AC.textLight, size: 20),
      const SizedBox(width: 8),
      Text(msg, style: const TextStyle(color: AC.textLight, fontSize: 13)),
    ]),
  );

  Widget _emptyStateCenter(String msg, IconData icon) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: AC.textLight, size: 48),
      const SizedBox(height: 12),
      Text(msg, style: const TextStyle(color: AC.textLight, fontSize: 14),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _smallBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(label, style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      );
    }