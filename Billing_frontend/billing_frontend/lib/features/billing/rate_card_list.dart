// ============================================================================
// rate_card_list.dart
// Abra Fleet Management - Rate Card List Screen
// Real-time table with filters, import/export, detail view, document download
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/create_rate_card_service.dart';
import 'create_rate_card.dart' as CreateRateCardModule;
import 'pages/rate_card_detail_screen.dart';

// Colors
const kPrimary   = Color(0xFF2C3E50);
const kBlue      = Color(0xFF3498DB);
const kGreen     = Color(0xFF27AE60);
const kOrange    = Color(0xFFE67E22);
const kRed       = Color(0xFFE74C3C);
const kGrey      = Color(0xFF7F8C8D);
const kLightGrey = Color(0xFFF5F6FA);
const kBorder    = Color(0xFFDFE6E9);

// ─── Table Column Config ─────────────────────────────────────────────────────
class _Column {
  final String label;
  final double width;
  final String key;
  const _Column(this.label, this.width, this.key);
}

const List<_Column> _columns = [
  _Column('Rate Card ID',    130, 'rateCardId'),
  _Column('Status',          110, 'status'),
  _Column('Organization',    180, 'organization'),
  _Column('Industry',        110, 'industry'),
  _Column('Contract Type',   110, 'contractType'),
  _Column('Route Code',      110, 'routeCode'),
  _Column('Route Name',      180, 'routeName'),
  _Column('Vehicle Type',    130, 'vehicleType'),
  _Column('Vehicles',         80, 'vehicles'),
  _Column('Billing Model',   150, 'billingModel'),
  _Column('Monthly Rate (₹)',140, 'monthlyRate'),
  _Column('Extra KM (₹)',   110, 'extraKm'),
  _Column('GST %',            80, 'gst'),
  _Column('Documents',        90, 'docs'),
  _Column('Contract Start',  120, 'contractStart'),
  _Column('Contract End',    120, 'contractEnd'),
  _Column('Created',         120, 'created'),
  _Column('Created By',      120, 'createdBy'),
  _Column('Actions',         120, 'actions'),
];

class RateCardListScreen extends StatefulWidget {
  const RateCardListScreen({Key? key}) : super(key: key);

  @override
  State<RateCardListScreen> createState() => _RateCardListScreenState();
}

class _RateCardListScreenState extends State<RateCardListScreen> {
  // ── Data State ──────────────────────────────────────────────────────────────
  List<RateCardModel> _rateCards = [];
  bool _isLoading = false;
  int _total = 0;
  int _totalPages = 1;
  Map<String, int> _stats = {};

  // ── Pagination ──────────────────────────────────────────────────────────────
  int _currentPage = 1;
  final int _limit = 20;

  // ── Filters ─────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String? _filterStatus;
  String? _filterBillingModel;
  String? _filterVehicleType;
  String? _filterIndustry;
  String? _filterContractType;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _sortBy    = 'createdAt';
  String _sortOrder = 'desc';

  // ── Scroll Controllers ───────────────────────────────────────────────────────
  final _vertScrollCtrl = ScrollController();
  final _horizScrollCtrl= ScrollController();

  // ── Import/Export ────────────────────────────────────────────────────────────
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadRateCards();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _vertScrollCtrl.dispose();
    _horizScrollCtrl.dispose();
    super.dispose();
  }

  // ── Debounced search ─────────────────────────────────────────────────────────
  void _onSearchChanged() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) { _currentPage = 1; _loadRateCards(); }
    });
  }

  // ── Load Rate Cards ──────────────────────────────────────────────────────────
  Future<void> _loadRateCards() async {
    setState(() => _isLoading = true);
    try {
      final response = await RateCardService.getRateCards(
        page: _currentPage,
        limit: _limit,
        status: _filterStatus,
        billingModel: _filterBillingModel,
        vehicleType: _filterVehicleType,
        industryType: _filterIndustry,
        contractType: _filterContractType,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        fromDate: _fromDate?.toIso8601String().split('T')[0],
        toDate:   _toDate?.toIso8601String().split('T')[0],
        sortBy:    _sortBy,
        sortOrder: _sortOrder,
      );
      setState(() {
        _rateCards  = response.rateCards;
        _total      = response.total;
        _totalPages = response.totalPages;
        _stats      = response.stats;
      });
    } catch (e) {
      _showSnackbar('Failed to load rate cards: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Status update ────────────────────────────────────────────────────────────
  Future<void> _updateStatus(RateCardModel rc, String newStatus) async {
    try {
      await RateCardService.updateStatus(rc.id, newStatus);
      _showSnackbar('Status updated to $newStatus');
      _loadRateCards();
    } catch (e) {
      _showSnackbar('Failed to update status: $e', isError: true);
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────────
  Future<void> _deleteRateCard(RateCardModel rc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Rate Card'),
        content: Text('Are you sure you want to delete ${rc.rateCardId}?\nThis action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await RateCardService.deleteRateCard(rc.id);
      _showSnackbar('Rate card deleted');
      _loadRateCards();
    } catch (e) {
      _showSnackbar('Delete failed: $e', isError: true);
    }
  }

  // ── Export CSV ───────────────────────────────────────────────────────────────
  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);
    try {
      final bytes = await RateCardService.exportCsv();
      if (kIsWeb) {
        // Web: trigger browser download
        // In real app, use dart:html or flutter_web_plugins
        _showSnackbar('CSV export ready (${bytes.length} bytes)');
      } else {
        final dir = Directory.systemTemp;
        final file = File('${dir.path}/rate_cards_${DateTime.now().millisecondsSinceEpoch}.csv');
        await file.writeAsBytes(bytes);
        _showSnackbar('Exported to: ${file.path}');
      }
    } catch (e) {
      _showSnackbar('Export failed: $e', isError: true);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // ── Import CSV ───────────────────────────────────────────────────────────────
  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      final file = File(result.files.first.path!);
      final response = await RateCardService.importCsv(file);
      _showSnackbar('Import: ${response['results']['imported']} records imported');
      _loadRateCards();
    } catch (e) {
      _showSnackbar('Import failed: $e', isError: true);
    } finally {
      setState(() => _isImporting = false);
    }
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? kRed : kGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kLightGrey,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildStatsBar(),
          _buildFilterBar(),
          Expanded(child: _buildTableSection()),
          _buildPaginationBar(),
        ],
      ),
    );
  }

  // ─── App Bar ─────────────────────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rate Cards', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text('Fleet Management — Trip Pricing Core', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      // ✅ NEW: Add back button to navigate to billing_main_shell
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Back to Finance Module',
      ),
      actions: [
        // Import
        if (!kIsWeb)
          IconButton(
            icon: _isImporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.upload_file),
            tooltip: 'Import CSV',
            onPressed: _isImporting ? null : _importCsv,
          ),

        // Export
        IconButton(
          icon: _isExporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.download),
          tooltip: 'Export CSV',
          onPressed: _isExporting ? null : _exportCsv,
        ),

        // Refresh
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _loadRateCards,
        ),

        // Create new
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 4),
          child: ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRateCardModule.CreateRateCardScreen()));
              if (result == true) _loadRateCards();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Rate Card'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Stats Bar ──────────────────────────────────────────────────────────────
  Widget _buildStatsBar() {
    final statItems = [
      {'label': 'Total', 'value': _total.toString(), 'color': kPrimary},
      {'label': 'Active', 'value': (_stats['Active'] ?? 0).toString(), 'color': kGreen},
      {'label': 'Draft', 'value': (_stats['Draft'] ?? 0).toString(), 'color': kOrange},
      {'label': 'Pending', 'value': (_stats['Pending Approval'] ?? 0).toString(), 'color': kBlue},
      {'label': 'Inactive', 'value': (_stats['Inactive'] ?? 0).toString(), 'color': kGrey},
      {'label': 'Expired', 'value': (_stats['Expired'] ?? 0).toString(), 'color': kRed},
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: statItems.map((s) {
          final color = s['color'] as Color;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(s['value']!.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  Text(s['label']!.toString(), style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Filter Bar ─────────────────────────────────────────────────────────────
  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              // Search
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by ID, organization, route...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtrl.clear(); _loadRateCards(); })
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Status filter
              _filterDropdown('Status', _filterStatus,
                ['Active', 'Draft', 'Inactive', 'Expired', 'Pending Approval'],
                (v) { setState(() => _filterStatus = v); _currentPage = 1; _loadRateCards(); }),
              const SizedBox(width: 8),

              // Billing Model filter
              _filterDropdown('Billing Model', _filterBillingModel,
                ['Dedicated Monthly', 'Per Trip', 'Hybrid'],
                (v) { setState(() => _filterBillingModel = v); _currentPage = 1; _loadRateCards(); }),
              const SizedBox(width: 8),

              // Vehicle Type filter
              _filterDropdown('Vehicle', _filterVehicleType,
                ['Sedan', 'Innova', 'Crysta', 'Tempo Traveller', 'Mini Bus', 'Large Bus'],
                (v) { setState(() => _filterVehicleType = v); _currentPage = 1; _loadRateCards(); }),
              const SizedBox(width: 8),

              // Industry filter
              _filterDropdown('Industry', _filterIndustry,
                ['IT', 'BPO', 'Hospital', 'Manufacturing', 'School', 'Finance', 'Retail', 'Other'],
                (v) { setState(() => _filterIndustry = v); _currentPage = 1; _loadRateCards(); }),
              const SizedBox(width: 8),

              // Date range
              OutlinedButton.icon(
                onPressed: _showDateRangePicker,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(
                  _fromDate != null ? '${DateFormat('dd/MM').format(_fromDate!)} - ${DateFormat('dd/MM').format(_toDate!)}' : 'Date Range',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _fromDate != null ? kBlue : kGrey,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(width: 8),

              // Clear filters
              if (_hasFilters)
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: kRed),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasFilters => _filterStatus != null || _filterBillingModel != null ||
      _filterVehicleType != null || _filterIndustry != null || _fromDate != null ||
      _searchCtrl.text.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _filterStatus = null; _filterBillingModel = null; _filterVehicleType = null;
      _filterIndustry = null; _fromDate = null; _toDate = null;
      _searchCtrl.clear(); _currentPage = 1;
    });
    _loadRateCards();
  }

  Future<void> _showDateRangePicker() async {
    final range = await showDialog<DateTimeRange>(
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
                  color: kBlue,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Select Date Range',
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
                      primary: kBlue,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                    ),
                  ),
                  child: CalendarDatePicker(
                    initialDate: _fromDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
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
                                    color: kBlue,
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
                                        primary: kBlue,
                                        onPrimary: Colors.white,
                                        surface: Colors.white,
                                      ),
                                    ),
                                    child: CalendarDatePicker(
                                      initialDate: date.add(const Duration(days: 1)),
                                      firstDate: date,
                                      lastDate: DateTime(2030),
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
    if (range != null) {
      setState(() { _fromDate = range.start; _toDate = range.end; _currentPage = 1; });
      _loadRateCards();
    }
  }

  Widget _filterDropdown(String hint, String? value, List<String> items, ValueChanged<String?> onChange) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        value: value,
        hint: Text(hint, style: const TextStyle(fontSize: 12)),
        items: [
          DropdownMenuItem<String>(value: null, child: Text('All $hint', style: const TextStyle(fontSize: 12))),
          ...items.map((i) => DropdownMenuItem<String>(value: i, child: Text(i, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChange,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          isDense: true,
        ),
        isExpanded: true,
      ),
    );
  }

  // ─── Table Section ──────────────────────────────────────────────────────────
  Widget _buildTableSection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kBlue));
    }

    if (_rateCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No rate cards found', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Create your first rate card to get started', style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRateCardModule.CreateRateCardScreen()));
                if (result == true) _loadRateCards();
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Rate Card'),
              style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Scrollbar(
          controller: _horizScrollCtrl,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _columns.fold<double>(0.0, (sum, col) => sum + (col.width ?? 0)),
              child: Column(
                children: [
                  _buildTableHeader(),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertScrollCtrl,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _vertScrollCtrl,
                        itemCount: _rateCards.length,
                        itemBuilder: (ctx, i) => _buildTableRow(_rateCards[i], i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Table Header ─────────────────────────────────────────────────────────
  Widget _buildTableHeader() {
    return Container(
      color: kPrimary,
      child: Row(
        children: _columns.map((col) => _headerCell(col)).toList(),
      ),
    );
  }

  Widget _headerCell(_Column col) {
    final isSorted = _sortBy == col.key;
    return InkWell(
      onTap: col.key != 'actions' && col.key != 'docs' ? () {
        setState(() {
          if (_sortBy == col.key) {
            _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
          } else {
            _sortBy = col.key;
            _sortOrder = 'asc';
          }
        });
        _loadRateCards();
      } : null,
      child: Container(
        width: col.width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                col.label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSorted)
              Icon(
                _sortOrder == 'asc' ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: Colors.white70,
              ),
          ],
        ),
      ),
    );
  }

  // ─── Table Row ────────────────────────────────────────────────────────────
  Widget _buildTableRow(RateCardModel rc, int index) {
    final isEven = index % 2 == 0;
    return InkWell(
      onTap: () => _showDetailSheet(rc),
      hoverColor: kBlue.withOpacity(0.05),
      child: Container(
        color: isEven ? Colors.white : kLightGrey,
        child: Row(
          children: [
            _cell(rc.rateCardId, _columns[0].width, bold: true, color: kBlue),
            _statusCell(rc.status, _columns[1].width),
            _cell(rc.organization.organizationName, _columns[2].width),
            _cell(rc.organization.industryType, _columns[3].width),
            _cell(rc.organization.contractType, _columns[4].width),
            _cell(rc.routeShift.routeCode, _columns[5].width, color: kGrey),
            _cell(rc.routeShift.routeName, _columns[6].width),
            _cell(rc.vehicle.vehicleType, _columns[7].width),
            _cell(rc.vehicle.numberOfVehicles.toString(), _columns[8].width, align: TextAlign.center),
            _billingModelCell(rc.pricing.billingModel, _columns[9].width),
            _cell('₹${_fmt(rc.pricing.monthlyBaseRatePerVehicle)}', _columns[10].width, align: TextAlign.right, bold: true),
            _cell('₹${_fmt(rc.pricing.extraKmRate)}/km', _columns[11].width, align: TextAlign.right),
            _cell('${rc.pricing.gstPercent}%', _columns[12].width, align: TextAlign.center),
            _docsCell(rc, _columns[13].width),
            _cell(_fmtDate(rc.organization.contractStartDate), _columns[14].width),
            _cell(_fmtDate(rc.organization.contractEndDate), _columns[15].width),
            _cell(_fmtDate(rc.createdAt), _columns[16].width),
            _cell(rc.createdBy, _columns[17].width),
            _actionsCell(rc, _columns[18].width),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, double width, {bool bold = false, Color? color, TextAlign align = TextAlign.left}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: color ?? kPrimary,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ),
    );
  }

  Widget _statusCell(String status, double width) {
    final configs = {
      'Active':           (kGreen, Icons.check_circle),
      'Draft':            (kOrange, Icons.edit),
      'Pending Approval': (kBlue, Icons.pending),
      'Inactive':         (kGrey, Icons.pause_circle),
      'Expired':          (kRed, Icons.cancel),
    };
    final config = configs[status] ?? (kGrey, Icons.help);

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (config.$1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (config.$1).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(config.$2, size: 12, color: config.$1),
              const SizedBox(width: 4),
              Flexible(child: Text(status, style: TextStyle(fontSize: 11, color: config.$1, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _billingModelCell(String model, double width) {
    final colors = {'Dedicated Monthly': kGreen, 'Per Trip': kBlue, 'Hybrid': kOrange};
    final color = colors[model] ?? kGrey;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(model, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Widget _docsCell(RateCardModel rc, double width) {
    final count = rc.documents.length;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: InkWell(
          onTap: count > 0 ? () => _showDetailSheet(rc, initialTab: 1) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: count > 0 ? kBlue.withOpacity(0.08) : Colors.grey.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.attach_file, size: 13, color: count > 0 ? kBlue : kGrey),
                const SizedBox(width: 4),
                Text('$count', style: TextStyle(fontSize: 12, color: count > 0 ? kBlue : kGrey, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionsCell(RateCardModel rc, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // View Detail
            IconButton(
              icon: const Icon(Icons.visibility, size: 18, color: kBlue),
              tooltip: 'View Details',
              onPressed: () => _showDetailSheet(rc),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
            // Edit
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: kOrange),
              tooltip: 'Edit',
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CreateRateCardModule.CreateRateCardScreen(existingCard: rc.toJson()),
                ));
                if (result == true) _loadRateCards();
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
            // More options
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: kGrey),
              padding: const EdgeInsets.all(4),
              onSelected: (action) async {
                switch (action) {
                  case 'activate':   await _updateStatus(rc, 'Active'); break;
                  case 'deactivate': await _updateStatus(rc, 'Inactive'); break;
                  case 'draft':      await _updateStatus(rc, 'Draft'); break;
                  case 'delete':     await _deleteRateCard(rc); break;
                }
              },
              itemBuilder: (ctx) => [
                if (rc.status != 'Active')
                  const PopupMenuItem(value: 'activate', child: Row(children: [Icon(Icons.check_circle, color: kGreen, size: 16), SizedBox(width: 8), Text('Set Active')])),
                if (rc.status == 'Active')
                  const PopupMenuItem(value: 'deactivate', child: Row(children: [Icon(Icons.pause, color: kGrey, size: 16), SizedBox(width: 8), Text('Deactivate')])),
                if (rc.status != 'Draft')
                  const PopupMenuItem(value: 'draft', child: Row(children: [Icon(Icons.edit, color: kOrange, size: 16), SizedBox(width: 8), Text('Move to Draft')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: kRed, size: 16), SizedBox(width: 8), Text('Delete', style: TextStyle(color: kRed))])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Detail Bottom Sheet ─────────────────────────────────────────────────────
  // ─── Navigate to Detail Screen ──────────────────────────────────────────────
  void _showDetailSheet(RateCardModel rc, {int initialTab = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RateCardDetailScreen(
          rateCardId: rc.id,
          authToken: null, // Add your auth token here if needed
        ),
      ),
    ).then((result) {
      // Reload the list if the rate card was updated
      if (result != null) {
        _loadRateCards();
      }
    });
  }

  // ─── Pagination Bar ─────────────────────────────────────────────────────────
  Widget _buildPaginationBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _limit + 1}–${(_currentPage * _limit).clamp(0, _total)} of $_total rate cards',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: _currentPage > 1 ? () { setState(() => _currentPage = 1); _loadRateCards(); } : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _loadRateCards(); } : null,
          ),
          ...List.generate(_totalPages, (i) => i + 1)
              .where((p) => (p - _currentPage).abs() <= 2)
              .map((p) => InkWell(
                onTap: () { setState(() => _currentPage = p); _loadRateCards(); },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: p == _currentPage ? kBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: p == _currentPage ? kBlue : kBorder),
                  ),
                  child: Center(child: Text('$p', style: TextStyle(color: p == _currentPage ? Colors.white : kPrimary, fontWeight: FontWeight.bold))),
                ),
              )),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < _totalPages ? () { setState(() => _currentPage++); _loadRateCards(); } : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed: _currentPage < _totalPages ? () { setState(() => _currentPage = _totalPages); _loadRateCards(); } : null,
          ),
        ],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────
  String _fmt(double v) => v == 0 ? '0' : NumberFormat('#,##0.##').format(v);
  String _fmtDate(DateTime d) => DateFormat('dd MMM yy').format(d);
}

// ============================================================================
// RATE CARD DETAIL BOTTOM SHEET
// ============================================================================
class _RateCardDetailSheet extends StatefulWidget {
  final RateCardModel rateCard;
  final int initialTab;
  final Function(String) onStatusChange;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RateCardDetailSheet({
    required this.rateCard,
    this.initialTab = 0,
    required this.onStatusChange,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_RateCardDetailSheet> createState() => _RateCardDetailSheetState();
}

class _RateCardDetailSheetState extends State<_RateCardDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final rc = widget.rateCard;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rc.rateCardId, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kPrimary)),
                        const SizedBox(height: 4),
                        Text(rc.organization.organizationName, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  _StatusBadge(rc.status),
                  const SizedBox(width: 12),
                  // Edit
                  OutlinedButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(foregroundColor: kOrange, side: const BorderSide(color: kOrange)),
                  ),
                  const SizedBox(width: 8),
                  // Status changer
                  PopupMenuButton<String>(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: kBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(children: [
                        Icon(Icons.swap_horiz, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Change Status', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ]),
                    ),
                    onSelected: widget.onStatusChange,
                    itemBuilder: (ctx) => ['Active', 'Draft', 'Inactive', 'Expired']
                        .where((s) => s != rc.status)
                        .map((s) => PopupMenuItem(value: s, child: Text(s)))
                        .toList(),
                  ),
                  const SizedBox(width: 8),
                  // Delete
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: kRed),
                    onPressed: widget.onDelete,
                  ),
                  // Close
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 20),

            // Tabs
            TabBar(
              controller: _tabCtrl,
              labelColor: kBlue,
              unselectedLabelColor: kGrey,
              indicatorColor: kBlue,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Overview'),
                Tab(icon: Icon(Icons.attach_file, size: 18), text: 'Documents'),
                Tab(icon: Icon(Icons.currency_rupee, size: 18), text: 'Pricing'),
                Tab(icon: Icon(Icons.verified_user, size: 18), text: 'SLA'),
                Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Billing'),
              ],
            ),

            const Divider(height: 1),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildOverviewTab(rc, scrollCtrl),
                  _buildDocumentsTab(rc),
                  _buildPricingTab(rc),
                  _buildSLATab(rc),
                  _buildBillingTab(rc),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Overview Tab ────────────────────────────────────────────────────────────
  Widget _buildOverviewTab(RateCardModel rc, ScrollController scrollCtrl) {
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(20),
      children: [
        _detailRow([
          _section('Organization', [
            _kv('Name', rc.organization.organizationName),
            _kv('Industry', rc.organization.industryType),
            _kv('Contact', rc.organization.contactPersonName),
            _kv('Phone', rc.organization.contactPhone),
            _kv('Email', rc.organization.contactEmail),
            _kv('Employees', rc.organization.numberOfEmployees.toString()),
            _kv('Contract', rc.organization.contractType),
            _kv('Start', DateFormat('dd MMM yyyy').format(rc.organization.contractStartDate)),
            _kv('End', DateFormat('dd MMM yyyy').format(rc.organization.contractEndDate)),
          ]),
          _section('Route & Shift', [
            _kv('Route Code', rc.routeShift.routeCode),
            _kv('Route Name', rc.routeShift.routeName),
            _kv('Pickup Zone', rc.routeShift.pickupZone),
            _kv('Drop Location', rc.routeShift.dropLocation),
            _kv('Distance', '${rc.routeShift.distanceKm} km'),
            _kv('Shift', rc.routeShift.shiftType),
            _kv('Pickup Time', rc.routeShift.pickupTime),
            _kv('Drop Time', rc.routeShift.dropTime),
            _kv('Trips/Day', rc.routeShift.tripsPerDay.toString()),
            _kv('Days', rc.routeShift.daysOfOperation),
          ]),
        ]),
        const SizedBox(height: 16),
        _detailRow([
          _section('Vehicle Details', [
            _kv('Type', rc.vehicle.vehicleType),
            _kv('Capacity', '${rc.vehicle.seatingCapacity} seats'),
            _kv('Vehicles', rc.vehicle.numberOfVehicles.toString()),
            _kv('Mode', rc.vehicle.vehicleMode),
            _kv('Driver', rc.vehicle.driverAssignment),
            _kv('GPS', rc.vehicle.gpsEnabled ? '✅ Yes' : '❌ No'),
            _kv('Women Only', rc.vehicle.isWomenOnlyVehicle ? '✅ Yes' : 'No'),
            _kv('Escort', rc.vehicle.escortRequired ? '✅ Yes' : 'No'),
            _kv('Driver BG Check', rc.vehicle.driverBgVerified ? '✅ Verified' : 'Pending'),
          ]),
          _section('Monthly Estimate', [
            _kvBold('Billing Model', rc.pricing.billingModel),
            _kvBold('Monthly Rate/Vehicle', '₹${NumberFormat('#,##0').format(rc.pricing.monthlyBaseRatePerVehicle)}'),
            _kvBold('Total Vehicles', rc.vehicle.numberOfVehicles.toString()),
            _kvBold('KM Included/Month', '${rc.pricing.kmIncludedPerMonth} km'),
            _kvBold('Extra KM Rate', '₹${rc.pricing.extraKmRate}/km'),
            _kvBold('GST', '${rc.pricing.gstPercent}%'),
            _kvBold('TDS', '${rc.pricing.tdsPercent}%'),
            const Divider(),
            _kvBold('Monthly Estimate (incl. GST)', '₹${NumberFormat('#,##0').format(rc.monthlyEstimate)}', highlight: true),
          ]),
        ]),
      ],
    );
  }

  // ─── Documents Tab ───────────────────────────────────────────────────────────
  Widget _buildDocumentsTab(RateCardModel rc) {
    if (rc.documents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No documents uploaded', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('${rc.documents.length} Document${rc.documents.length != 1 ? 's' : ''} Attached',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kPrimary)),
        const SizedBox(height: 16),
        ...rc.documents.map((doc) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              // Doc icon
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(color: _docColor(doc.fileName).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(_docIcon(doc.fileName), color: _docColor(doc.fileName), size: 28),
              ),
              const SizedBox(width: 14),

              // Doc info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.documentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kPrimary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: kBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(doc.documentType, style: const TextStyle(fontSize: 11, color: kBlue)),
                        ),
                        const SizedBox(width: 8),
                        Text(doc.fileSizeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(width: 8),
                        Text(DateFormat('dd MMM yyyy').format(doc.uploadedAt), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Uploaded by: ${doc.uploadedBy}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ),

              // Action buttons
              const SizedBox(width: 12),
              Column(
                children: [
                  // VIEW button
                  OutlinedButton.icon(
                    onPressed: () => _openDocument(rc.id, doc.id, download: false),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kBlue,
                      side: const BorderSide(color: kBlue),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // DOWNLOAD button
                  ElevatedButton.icon(
                    onPressed: () => _openDocument(rc.id, doc.id, download: true),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        )),
      ],
    );
  }

  Future<void> _openDocument(String rcId, String docId, {required bool download}) async {
    final url = RateCardService.getDocumentUrl(rcId, docId, download: download);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot open document. Check network.'),
          backgroundColor: kRed,
        ));
      }
    }
  }

  // ─── Pricing Tab ─────────────────────────────────────────────────────────────
  Widget _buildPricingTab(RateCardModel rc) {
    final p = rc.pricing;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _detailRow([
          _section('Pricing Core', [
            _kvBold('Billing Model', p.billingModel),
            if (p.billingModel != 'Per Trip') ...[
              _kv('Monthly Base Rate/Vehicle', '₹${NumberFormat('#,##0').format(p.monthlyBaseRatePerVehicle)}'),
              _kv('KM Included/Month', '${p.kmIncludedPerMonth} km'),
              _kv('Extra KM Rate', '₹${p.extraKmRate}/km'),
            ],
            if (p.billingModel == 'Per Trip') ...[
              _kv('Per Trip Rate', '₹${p.perTripRate}'),
              _kv('Zone 1 (0–10km)', '₹${p.zone1Rate}/trip'),
              _kv('Zone 2 (10–20km)', '₹${p.zone2Rate}/trip'),
              _kv('Zone 3 (20–30km)', '₹${p.zone3Rate}/trip'),
              _kv('Zone 4 (30+km)', '₹${p.zone4Rate}/trip'),
            ],
          ]),
          _section('Surcharges', [
            _kv('Night Shift Surcharge', '₹${p.nightShiftSurcharge}/trip (after ${p.nightShiftStartTime})'),
            _kv('Weekend Surcharge', '${p.weekendSurchargePercent}%'),
            _kv('Festival Rate', '${p.festivalHolidayRatePercent}%'),
            _kv('Driver Bata', '₹${p.driverBataPerDay}/day'),
            _kv('Escort Charge', '₹${p.escortChargePerTrip}/trip'),
            _kv('Cancellation Charge', '₹${p.cancellationChargeOrg}'),
          ]),
        ]),
        const SizedBox(height: 16),
        _detailRow([
          _section('Inclusions', [
            _kv('Driver Bata', p.driverBataIncluded ? '✅ Included' : '❌ Extra'),
            _kv('Toll Charges', p.tollChargesIncluded ? '✅ Included' : '❌ Extra (Actuals)'),
            _kv('Parking', p.parkingChargesIncluded ? '✅ Included' : '❌ Extra'),
            _kv('State Permit', p.statePermitIncluded ? '✅ Included' : '❌ Extra'),
            _kv('Fuel', p.fuelIncluded ? '✅ Included' : '❌ Separate'),
            _kv('Fuel Escalation', p.fuelEscalationLinked ? '✅ Linked' : 'Fixed'),
          ]),
          _section('Tax', [
            _kvBold('GST', '${p.gstPercent}% on transport'),
            _kvBold('TDS', '${p.tdsPercent}% (Org deducts)'),
            _kv('No-Show Billable', p.noShowBillable ? '✅ Yes' : '❌ Not billed'),
          ]),
        ]),
      ],
    );
  }

  // ─── SLA Tab ─────────────────────────────────────────────────────────────────
  Widget _buildSLATab(RateCardModel rc) {
    final s = rc.sla;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _section('SLA Commitments', [
          _kvBold('On-Time Pickup Guarantee', '${s.onTimePickupGuaranteePercent}%'),
          _kv('Max Delay Allowed', '${s.maxDelayAllowedMinutes} minutes'),
          _kv('Breakdown Response', '${s.breakdownResponseMinutes} minutes'),
          _kv('Escalation Contact', s.escalationContact.isEmpty ? 'Not set' : s.escalationContact),
          _kv('Monthly MIS Report', s.monthlyMISReport ? '✅ Yes' : 'No'),
        ]),
        const SizedBox(height: 16),
        _section('Penalties (Auto-deducted from invoice)', [
          _kvBold('Per Late Trip', '₹${s.penaltyPerLateTrip}'),
          _kvBold('No Replacement Penalty', '₹${s.penaltyNoReplacement}'),
        ]),
      ],
    );
  }

  // ─── Billing Tab ─────────────────────────────────────────────────────────────
  Widget _buildBillingTab(RateCardModel rc) {
    final b = rc.organization;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _section('Invoice Details', [
          _kv('Invoice Frequency', 'Monthly'),
          _kv('Invoice Due Date', '${7}th of every month'),
          _kv('Payment Mode', 'NEFT'),
          _kv('Late Payment Penalty', '2%/day'),
        ]),
        const SizedBox(height: 16),
        _section('Security & Escalation', [
          _kv('Security Deposit', '1 month advance'),
          _kv('Price Revision', 'After 6 months'),
          _kv('Revision Linked To', 'Fuel Price Index'),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kGreen.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kGreen.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              const Text('Invoice Formula', style: TextStyle(fontWeight: FontWeight.bold, color: kPrimary, fontSize: 15)),
              const SizedBox(height: 12),
              const Text(
                'Monthly Base Rate × Vehicles\n'
                '+ Extra KM × Extra KM Rate\n'
                '+ Night Trips × Night Surcharge\n'
                '+ Toll Actuals\n'
                '− SLA Penalty Deductions\n'
                '+ GST 5%\n'
                '═══════════════════\n'
                'FINAL MONTHLY INVOICE',
                style: TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.8, color: kPrimary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Detail Helpers ───────────────────────────────────────────────────────────
  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary, fontSize: 14)),
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, child: Text(k, style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13, color: kPrimary))),
      ],
    ),
  );

  Widget _kvBold(String k, String v, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, child: Text(k, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimary))),
        Expanded(child: Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: highlight ? kGreen : kPrimary))),
      ],
    ),
  );

  Widget _detailRow(List<Widget> children) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children.asMap().entries.map((e) => Expanded(
      child: Padding(padding: EdgeInsets.only(left: e.key > 0 ? 12 : 0), child: e.value),
    )).toList(),
  );

  IconData _docIcon(String fn) {
    final ext = fn.toLowerCase().split('.').last;
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (['jpg','jpeg','png'].contains(ext)) return Icons.image;
    if (['doc','docx'].contains(ext)) return Icons.article;
    if (['xlsx','xls'].contains(ext)) return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  Color _docColor(String fn) {
    final ext = fn.toLowerCase().split('.').last;
    if (ext == 'pdf') return kRed;
    if (['jpg','jpeg','png'].contains(ext)) return kGreen;
    if (['doc','docx'].contains(ext)) return kBlue;
    if (['xlsx','xls'].contains(ext)) return Color(0xFF1D6F42);
    return kGrey;
  }
}

// ─── Status Badge Widget ─────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final configs = {
      'Active':           (kGreen, Icons.check_circle),
      'Draft':            (kOrange, Icons.edit),
      'Pending Approval': (kBlue, Icons.pending),
      'Inactive':         (kGrey, Icons.pause_circle),
      'Expired':          (kRed, Icons.cancel),
    };
    final config = configs[status] ?? (kGrey, Icons.help);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (config.$1).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (config.$1).withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.$2, size: 14, color: config.$1),
          const SizedBox(width: 6),
          Text(status, style: TextStyle(color: config.$1, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}