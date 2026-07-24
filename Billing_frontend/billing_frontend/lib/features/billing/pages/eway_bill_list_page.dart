import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// E-WAY BILL LIST PAGE
// ============================================================================
// File: lib/screens/billing/eway_bills/eway_bill_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/eway_bill_service.dart';
import '../app_top_bar.dart';
import 'eway_bill_forms.dart';

// ── color palette (matches existing app) ──────────────────────────────────
const Color _navy = Color(0xFF1e3a8a);
const Color _navyDark = Color(0xFF0D1B3E);
const Color _green = Color(0xFF27AE60);
const Color _blue = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red = Color(0xFFE74C3C);
const Color _purple = Color(0xFF9B59B6);

class EWayBillListPage extends StatefulWidget {
  const EWayBillListPage({Key? key}) : super(key: key);

  @override
  State<EWayBillListPage> createState() => _EWayBillListPageState();
}

class _EWayBillListPageState extends State<EWayBillListPage> {
  // ── connection state ──────────────────────────────────────────────────────
  EWBConnectionStatus? _connectionStatus;
  bool _loadingStatus = true;

  // ── list data ─────────────────────────────────────────────────────────────
  List<EWayBillModel> _ewbs = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String _selectedStatus = 'All';
  String _selectedSource = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showAdvancedFilters = false;

  final List<String> _statusFilters = [
    'All',
    'GENERATED',
    'PART_A',
    'EXTENDED',
    'EXPIRED',
    'CANCELLED'
  ];
  final List<String> _sourceFilters = [
    'All',
    'INVOICE',
    'CREDIT_NOTE',
    'DELIVERY_CHALLAN'
  ];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  final int _limit = 20;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableScroll = ScrollController();

  // ── connect form ──────────────────────────────────────────────────────────
  final _gstinCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _gstinCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _tableScroll.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadStatus() async {
    try {
      final res = await EWayBillService.getConnectionStatus();
      setState(() {
        _connectionStatus = EWBConnectionStatus.fromJson(res['data'] ?? {});
        _loadingStatus = false;
      });
      if (_connectionStatus!.isConnected) _loadEWBs();
    } catch (e) {
      setState(() {
        _loadingStatus = false;
      });
    }
  }

  Future<void> _loadEWBs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final res = await EWayBillService.getEWayBills(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        sourceType: _selectedSource == 'All' ? null : _selectedSource,
        fromDate: _fromDate?.toIso8601String(),
        toDate: _toDate?.toIso8601String(),
        search:
            _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        page: _currentPage,
        limit: _limit,
      );
      final list = (res['data'] as List? ?? [])
          .map((e) => EWayBillModel.fromJson(e))
          .toList();
      final pagination = res['pagination'] as Map? ?? {};
      setState(() {
        _ewbs = list;
        _stats = res['stats'] as Map<String, dynamic>? ?? {};
        _totalCount = pagination['total'] ?? 0;
        _totalPages = pagination['pages'] ?? 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _refresh() async {
    _currentPage = 1;
    await _loadEWBs();
  }

  // ── connect ───────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final gstin = _gstinCtrl.text.trim().toUpperCase();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (gstin.isEmpty || username.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    if (gstin.length != 15) {
      _showError('GSTIN must be exactly 15 characters');
      return;
    }

    setState(() => _connecting = true);
    try {
      final res = await EWayBillService.connectPortal(
          gstin: gstin, username: username, password: password);
      setState(() => _connecting = false);
      if (res['success'] == true) {
        _showSuccess(res['message'] ?? 'Connected successfully');
        await _loadStatus();
      } else {
        _showError(res['message'] ?? 'Connection failed');
      }
    } catch (e) {
      setState(() => _connecting = false);
      _showError(e.toString());
    }
  }

  Future<void> _disconnect() async {
    final ok = await _confirmDialog(
      title: 'Disconnect EWB Portal',
      message:
          'Are you sure you want to disconnect from the EWB portal? You will not be able to generate new e-Way Bills.',
      confirmLabel: 'Disconnect',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await EWayBillService.disconnectPortal();
      _showSuccess('Disconnected from EWB portal');
      _loadStatus();
    } catch (e) {
      _showError(e.toString());
    }
  }

  // ── navigation ────────────────────────────────────────────────────────────

  Future<void> _openGenerate() async {
    if (_connectionStatus?.isConnected != true) {
      _showError('Please connect to EWB portal first');
      return;
    }
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const EWayBillGenerateForm()));
    if (ok == true) _loadEWBs();
  }

  Future<void> _openDetail(EWayBillModel ewb) async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => EWayBillDetailPage(ewbId: ewb.id)));
    if (ok == true) _loadEWBs();
  }

  Future<void> _openConsolidated() async {
    if (_connectionStatus?.isConnected != true) {
      _showError('Please connect to EWB portal first');
      return;
    }
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ConsolidatedEWBForm()));
    if (ok == true) _loadEWBs();
  }

  // ── filter helpers ────────────────────────────────────────────────────────

  bool get _hasFilter =>
      _selectedStatus != 'All' ||
      _selectedSource != 'All' ||
      _fromDate != null ||
      _toDate != null ||
      _searchCtrl.text.isNotEmpty;

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _selectedStatus = 'All';
      _selectedSource = 'All';
      _fromDate = null;
      _toDate = null;
      _currentPage = 1;
      _showAdvancedFilters = false;
    });
    _loadEWBs();
  }

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (c, child) => Theme(
          data: Theme.of(c)
              .copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
          child: child!),
    );
    if (d != null) {
      setState(() {
        isFrom ? _fromDate = d : _toDate = d;
        _currentPage = 1;
      });
      _loadEWBs();
    }
  }

  // ── snackbars / dialogs ───────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  void _showError(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  Future<bool?> _confirmDialog(
          {required String title,
          required String message,
          required String confirmLabel,
          Color confirmColor = _navy}) =>
      showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                content: Text(message),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: confirmColor,
                          foregroundColor: Colors.white),
                      child: Text(confirmLabel)),
                ],
              ));

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'e-Way Bills'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : _connectionStatus?.isConnected == true
              ? _buildConnectedUI()
              : _buildConnectionForm(),
    );
  }

  // ─── NOT CONNECTED: show connection form ────────────────────────────────

  Widget _buildConnectionForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_navyDark, _navy],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: _navy.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8))
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.receipt_long_rounded,
                            color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 16),
                      const Text('e-Way Bill Portal',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(
                          'Connect your EWB portal account to start generating e-Way Bills for your invoices.',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                              height: 1.5)),
                    ]),
              ),

              const SizedBox(height: 24),

              // Info chips
              Wrap(spacing: 8, runSpacing: 8, children: [
                _infoChip('📋 Invoice linked', _blue),
                _infoChip('🔒 Credentials encrypted', _green),
                _infoChip('🔄 Auto token refresh', _purple),
                _infoChip('📤 Direct NIC connection', _orange),
              ]),

              const SizedBox(height: 24),

              // Form card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('EWB Portal Credentials',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _navyDark)),
                      const SizedBox(height: 6),
                      Text(
                          'Use the same credentials you use on ewaybillgst.gov.in',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 20),

                      // GSTIN
                      _buildFormLabel('GSTIN *'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _gstinCtrl,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 15,
                        decoration: _inputDecoration(
                            hint: 'e.g. 22AAAAA0000A1Z5', icon: Icons.business),
                      ),
                      const SizedBox(height: 16),

                      // Username
                      _buildFormLabel('EWB Portal Username *'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _usernameCtrl,
                        decoration: _inputDecoration(
                            hint: 'Your EWB portal username',
                            icon: Icons.person_outline),
                      ),
                      const SizedBox(height: 16),

                      // Password
                      _buildFormLabel('EWB Portal Password *'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePass,
                        decoration: _inputDecoration(
                                hint: 'Your EWB portal password',
                                icon: Icons.lock_outline)
                            .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscurePass
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                                size: 20),
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Connect button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _connecting ? null : _connect,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _connecting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                      Icon(Icons.link_rounded, size: 20),
                                      SizedBox(width: 8),
                                      Text('Connect Now',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                    ]),
                        ),
                      ),
                    ]),
              ),

              const SizedBox(height: 16),
              // Help note
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber[300]!)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.amber[800], size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                        'The finance team needs to first register on the EWB portal (ewaybillgst.gov.in) and create credentials. Those same credentials are entered here.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[900],
                            height: 1.5),
                      )),
                    ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CONNECTED: show full list ───────────────────────────────────────────

  Widget _buildConnectedUI() {
    return SingleChildScrollView(
      child: Column(children: [
        _buildTopBar(),
        if (_showAdvancedFilters) _buildAdvancedFilters(),
        // ── Smart notification banner ──────────────────────────────────────
        EWBPendingBanner(
          onTap: () {
            AppSnackbar.show(context,
                message:
                    'Navigate to Invoices and generate EWB for those > ₹50,000');
          },
        ),
        _buildStatsCards(),
        if (_isLoading)
          const SizedBox(
              height: 400,
              child: Center(child: CircularProgressIndicator(color: _navy)))
        else if (_errorMessage != null)
          _buildError()
        else if (_ewbs.isEmpty)
          _buildEmpty()
        else
          _buildTable(),
        if (!_isLoading && _ewbs.isNotEmpty) _buildPagination(),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700) return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
        _statusDropdown(),
        const SizedBox(width: 10),
        _sourceDropdown(),
        const SizedBox(width: 10),
        _searchField(width: 210),
        const SizedBox(width: 8),
        _dateChip(
            label: _fromDate != null
                ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                : 'From Date',
            isActive: _fromDate != null,
            onTap: () => _pickDate(true)),
        const SizedBox(width: 6),
        _dateChip(
            label: _toDate != null
                ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                : 'To Date',
            isActive: _toDate != null,
            onTap: () => _pickDate(false)),
        if (_fromDate != null || _toDate != null) ...[
          const SizedBox(width: 4),
          _iconBtn(Icons.close, () {
            setState(() {
              _fromDate = null;
              _toDate = null;
              _currentPage = 1;
            });
            _loadEWBs();
          }, color: _red),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.filter_list,
            () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
            color: _showAdvancedFilters ? _navy : Colors.grey),
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _refresh, tooltip: 'Refresh'),
        const Spacer(),
        // Connected badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: _green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _green.withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    const BoxDecoration(color: _green, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
                'Connected${_connectionStatus?.gstin != null ? " · ${_connectionStatus!.gstin}" : ""}',
                style: const TextStyle(
                    fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            InkWell(
                onTap: _disconnect,
                child: Icon(Icons.link_off,
                    size: 14, color: _green.withOpacity(0.7))),
          ]),
        ),
        const SizedBox(width: 12),
        _actionBtn('Consolidated EWB', _purple, _openConsolidated),
        const SizedBox(width: 8),
        _actionBtn('+ New EWB', _navy, _openGenerate),
      ]);

  Widget _topBarTablet() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _statusDropdown(),
          const SizedBox(width: 8),
          _sourceDropdown(),
          const SizedBox(width: 8),
          Expanded(child: _searchField(width: double.infinity)),
          const SizedBox(width: 8),
          _iconBtn(Icons.refresh_rounded, _refresh, tooltip: 'Refresh'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _dateChip(
              label: _fromDate != null
                  ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                  : 'From Date',
              isActive: _fromDate != null,
              onTap: () => _pickDate(true)),
          const SizedBox(width: 6),
          _dateChip(
              label: _toDate != null
                  ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                  : 'To Date',
              isActive: _toDate != null,
              onTap: () => _pickDate(false)),
          const Spacer(),
          _connectedBadge(),
          const SizedBox(width: 10),
          _actionBtn('+ New EWB', _navy, _openGenerate),
        ]),
      ]);

  Widget _topBarMobile() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _searchField(width: double.infinity)),
          const SizedBox(width: 8),
          _actionBtn('+ New', _navy, _openGenerate),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _statusDropdown(),
              const SizedBox(width: 8),
              _sourceDropdown(),
              const SizedBox(width: 8),
              _iconBtn(Icons.refresh_rounded, _refresh),
              const SizedBox(width: 8),
              _connectedBadge(),
            ])),
      ]);

  Widget _connectedBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: _green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _green.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: _green, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          const Text('Connected',
              style: TextStyle(
                  fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _buildAdvancedFilters() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFF7F9FC),
        child: Row(children: [
          const Text('Advanced Filters:',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(width: 12),
          if (_hasFilter)
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear, size: 14),
              label: const Text('Clear All', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: _red),
            ),
        ]),
      );

  // ── stats cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final cards = [
      _cardData('Total EWBs', '${_stats['total'] ?? 0}', Icons.receipt_long,
          _navy, [const Color(0xFF2463AE), _navy]),
      _cardData(
          'Generated',
          '${_stats['generated'] ?? 0}',
          Icons.check_circle_outline,
          _green,
          [const Color(0xFF2ECC71), _green]),
      _cardData('Part A Only', '${_stats['partA'] ?? 0}', Icons.pending_actions,
          _orange, [const Color(0xFFF39C12), _orange]),
      _cardData('Expired', '${_stats['expired'] ?? 0}',
          Icons.timer_off_outlined, _red, [const Color(0xFFFF6B6B), _red]),
      _cardData('Cancelled', '${_stats['cancelled'] ?? 0}',
          Icons.cancel_outlined, _purple, [const Color(0xFFBB8FCE), _purple]),
    ];
    return Container(
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                  children: cards
                      .asMap()
                      .entries
                      .map((e) => Container(
                          width: 155,
                          margin: EdgeInsets.only(
                              right: e.key < cards.length - 1 ? 10 : 0),
                          child: _statCard(e.value, compact: true)))
                      .toList()));
        }
        return Row(
            children: cards
                .asMap()
                .entries
                .map((e) => Expanded(
                    child: Padding(
                        padding: EdgeInsets.only(
                            right: e.key < cards.length - 1 ? 10 : 0),
                        child: _statCard(e.value, compact: false))))
                .toList());
      }),
    );
  }

  Map<String, dynamic> _cardData(String label, String value, IconData icon,
          Color color, List<Color> grad) =>
      {
        'label': label,
        'value': value,
        'icon': icon,
        'color': color,
        'grad': grad
      };

  Widget _statCard(Map<String, dynamic> d, {required bool compact}) {
    return Container(
      padding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          (d['grad'] as List<Color>)[0].withOpacity(0.15),
          (d['grad'] as List<Color>)[1].withOpacity(0.08)
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (d['color'] as Color).withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
              color: (d['color'] as Color).withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: d['grad'] as List<Color>,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(d['icon'] as IconData,
                          color: Colors.white, size: 20)),
                  const SizedBox(height: 10),
                  Text(d['label'] as String,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(d['value'] as String,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: d['color'] as Color)),
                ])
          : Row(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: d['grad'] as List<Color>,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: (d['color'] as Color).withOpacity(0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ]),
                  child: Icon(d['icon'] as IconData,
                      color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(d['label'] as String,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Text(d['value'] as String,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: d['color'] as Color)),
                  ])),
            ]),
    );
  }

  // ── table ─────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ]),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableScroll,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 7,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad
            }),
            child: SingleChildScrollView(
              controller: _tableScroll,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(_navyDark),
                  headingTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.4),
                  headingRowHeight: 52,
                  dataRowMinHeight: 62,
                  dataRowMaxHeight: 80,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dividerThickness: 1,
                  columnSpacing: 18,
                  horizontalMargin: 16,
                  dataRowColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.hovered)
                          ? _navy.withOpacity(0.04)
                          : null),
                  columns: const [
                    DataColumn(
                        label: SizedBox(width: 140, child: Text('EWB NUMBER'))),
                    DataColumn(
                        label: SizedBox(width: 140, child: Text('DOCUMENT'))),
                    DataColumn(
                        label: SizedBox(
                            width: 160, child: Text('CUSTOMER/VENDOR'))),
                    DataColumn(
                        label: SizedBox(width: 100, child: Text('AMOUNT'))),
                    DataColumn(
                        label:
                            SizedBox(width: 130, child: Text('VALID UNTIL'))),
                    DataColumn(
                        label: SizedBox(width: 120, child: Text('STATUS'))),
                    DataColumn(
                        label: SizedBox(width: 100, child: Text('ACTIONS'))),
                  ],
                  rows: _ewbs.map(_buildRow).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(EWayBillModel ewb) {
    return DataRow(cells: [
      // EWB Number
      DataCell(SizedBox(
          width: 140,
          child: InkWell(
            onTap: () => _openDetail(ewb),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(ewb.ewbNumber ?? 'Part A Only',
                      style: TextStyle(
                          color: ewb.ewbNumber != null ? _navy : _orange,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          decoration: ewb.ewbNumber != null
                              ? TextDecoration.underline
                              : null)),
                  if (ewb.isManuallyAssociated)
                    Text('Manual',
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[500])),
                ]),
          ))),

      // Document
      DataCell(SizedBox(
          width: 140,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(ewb.sourceNumber,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 12)),
                Text(ewb.sourceType.replaceAll('_', ' '),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ]))),

      // Customer
      DataCell(SizedBox(
          width: 160,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(ewb.toTradeName.isNotEmpty ? ewb.toTradeName : 'N/A',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 12)),
                if (ewb.toGstin.isNotEmpty)
                  Text(ewb.toGstin,
                      style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ]))),

      // Amount
      DataCell(SizedBox(
          width: 100,
          child: Text('₹${ewb.totalInvoiceValue.toStringAsFixed(2)}',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)))),

      // Valid Until
      DataCell(SizedBox(
          width: 130,
          child: ewb.validUntil != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                      Text(DateFormat('dd MMM yyyy').format(ewb.validUntil!),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      Text(ewb.validityText,
                          style: TextStyle(
                              fontSize: 10,
                              color: ewb.isExpired
                                  ? _red
                                  : ewb.canExtend
                                      ? _orange
                                      : _green,
                              fontWeight: FontWeight.w500)),
                    ])
              : const Text('—',
                  style: TextStyle(fontSize: 12, color: Colors.grey)))),

      // Status
      DataCell(SizedBox(width: 120, child: _statusBadge(ewb.ewbStatus))),

      // Actions
      DataCell(SizedBox(
          width: 100,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem(
                  'view', Icons.visibility_outlined, _blue, 'View Details'),
              if (ewb.isActive || ewb.isPartA)
                _menuItem('update_vehicle', Icons.local_shipping_outlined,
                    _orange, 'Update Vehicle'),
              if (ewb.canExtend)
                _menuItem(
                    'extend', Icons.timer_outlined, _green, 'Extend Validity'),
              if (ewb.canCancel)
                _menuItem('cancel', Icons.cancel_outlined, _red, 'Cancel EWB'),
              _menuItem('associate', Icons.link, _blue, 'Associate EWB'),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'view':
                  _openDetail(ewb);
                  break;
                case 'update_vehicle':
                  _openDetail(ewb);
                  break;
                case 'extend':
                  _openDetail(ewb);
                  break;
                case 'cancel':
                  _openDetail(ewb);
                  break;
                case 'associate':
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AssociateEWBDialog(
                            sourceType: ewb.sourceType,
                            sourceId: ewb.sourceId,
                            sourceNumber: ewb.sourceNumber,
                          ));
                  if (ok == true) _loadEWBs();
                  break;
              }
            },
          ))),
    ]);
  }

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'GENERATED': [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'PART_A': [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'EXTENDED': [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'EXPIRED': [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'CANCELLED': [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'DRAFT': [Color(0xFFF1F5F9), Color(0xFF94A3B8)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: c[0],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status.replaceAll('_', ' '),
            style: TextStyle(
                color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  PopupMenuItem<String> _menuItem(
          String value, IconData icon, Color color, String label) =>
      PopupMenuItem(
          value: value,
          child: ListTile(
            leading: Icon(icon, size: 17, color: color),
            title: Text(label,
                style: TextStyle(
                    fontSize: 13, color: label == 'Cancel EWB' ? _red : null)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ));

  // ── pagination ────────────────────────────────────────────────────────────

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final start = (_currentPage - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: LayoutBuilder(
          builder: (_, c) => Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  Text(
                      'Showing ${(_currentPage - 1) * _limit + 1}–${(_currentPage * _limit).clamp(0, _totalCount)} of $_totalCount',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _pageNavBtn(Icons.chevron_left, _currentPage > 1, () {
                      setState(() => _currentPage--);
                      _loadEWBs();
                    }),
                    const SizedBox(width: 4),
                    if (pages.first > 1) ...[
                      _pageNumBtn(1),
                      if (pages.first > 2)
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text('…',
                                style: TextStyle(color: Colors.grey[400])))
                    ],
                    ...pages.map(_pageNumBtn),
                    if (pages.last < _totalPages) ...[
                      if (pages.last < _totalPages - 1)
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text('…',
                                style: TextStyle(color: Colors.grey[400]))),
                      _pageNumBtn(_totalPages)
                    ],
                    const SizedBox(width: 4),
                    _pageNavBtn(Icons.chevron_right, _currentPage < _totalPages,
                        () {
                      setState(() => _currentPage++);
                      _loadEWBs();
                    }),
                  ]),
                ],
              )),
    );
  }

  Widget _pageNumBtn(int p) {
    final isActive = _currentPage == p;
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          setState(() => _currentPage = p);
          _loadEWBs();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: isActive ? _navy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? _navy : Colors.grey[300]!)),
        child: Center(
            child: Text('$p',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? Colors.white : Colors.grey[700]))),
      ),
    );
  }

  Widget _pageNavBtn(IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: enabled ? Colors.white : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!)),
              child: Icon(icon,
                  size: 18, color: enabled ? _navy : Colors.grey[300])));

  // ── empty / error ─────────────────────────────────────────────────────────

  Widget _buildEmpty() => SizedBox(
      height: 400,
      child: Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                            color: _navy.withOpacity(0.06),
                            shape: BoxShape.circle),
                        child: Icon(Icons.receipt_long_outlined,
                            size: 64, color: _navy.withOpacity(0.4))),
                    const SizedBox(height: 20),
                    const Text('No e-Way Bills Found',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A202C))),
                    const SizedBox(height: 8),
                    Text(
                        _hasFilter
                            ? 'Try adjusting your filters'
                            : 'Generate your first e-Way Bill',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[500])),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: _hasFilter ? _clearFilters : _openGenerate,
                      icon:
                          Icon(_hasFilter ? Icons.filter_list_off : Icons.add),
                      label: Text(_hasFilter ? 'Clear Filters' : 'Generate EWB',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                  ]))));

  Widget _buildError() => SizedBox(
      height: 400,
      child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            padding: const EdgeInsets.all(24),
            decoration:
                BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
            child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
        const SizedBox(height: 20),
        const Text('Failed to Load e-Way Bills',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_errorMessage ?? 'Unknown error',
            style: TextStyle(color: Colors.grey[500]),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        ElevatedButton.icon(
            onPressed: _loadEWBs,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)))),
      ])));

  // ── reusable widgets ──────────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            border: Border.all(color: const Color(0xFFDDE3EE)),
            borderRadius: BorderRadius.circular(10)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
          value: _selectedStatus,
          icon: const Icon(Icons.expand_more, size: 18, color: _navy),
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
          items: _statusFilters
              .map((s) => DropdownMenuItem(
                  value: s,
                  child:
                      Text(s == 'All' ? 'All Status' : s.replaceAll('_', ' '))))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedStatus = v;
                _currentPage = 1;
              });
              _loadEWBs();
            }
          },
        )),
      );

  Widget _sourceDropdown() => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            border: Border.all(color: const Color(0xFFDDE3EE)),
            borderRadius: BorderRadius.circular(10)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
          value: _selectedSource,
          icon: const Icon(Icons.expand_more, size: 18, color: _navy),
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
          items: _sourceFilters
              .map((s) => DropdownMenuItem(
                  value: s,
                  child:
                      Text(s == 'All' ? 'All Types' : s.replaceAll('_', ' '))))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedSource = v;
                _currentPage = 1;
              });
              _loadEWBs();
            }
          },
        )),
      );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchCtrl,
      onSubmitted: (_) {
        setState(() => _currentPage = 1);
        _loadEWBs();
      },
      decoration: InputDecoration(
        hintText: 'Search EWB#, invoice, customer…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _currentPage = 1);
                  _loadEWBs();
                })
            : null,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (width == double.infinity) return SizedBox(height: 44, child: field);
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _dateChip(
          {required String label,
          required bool isActive,
          required VoidCallback onTap}) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: isActive
                      ? _navy.withOpacity(0.08)
                      : const Color(0xFFF7F9FC),
                  border: Border.all(
                      color: isActive ? _navy : const Color(0xFFDDE3EE)),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today,
                    size: 15, color: isActive ? _navy : Colors.grey[500]),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive ? _navy : Colors.grey[600])),
              ])));

  Widget _iconBtn(IconData icon, VoidCallback? onTap,
          {String tooltip = '', Color color = const Color(0xFF7F8C8D)}) =>
      Tooltip(
          message: tooltip,
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withOpacity(0.25))),
                  child: Icon(icon,
                      size: 20,
                      color: onTap == null ? Colors.grey[300] : color))));

  Widget _actionBtn(String label, Color bg, VoidCallback? onTap) =>
      ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));

  Widget _infoChip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)));

  InputDecoration _inputDecoration(
          {required String hint, required IconData icon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, size: 20, color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
        counterText: '',
      );

  Widget _buildFormLabel(String label) => Text(label,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: _navyDark));
}
