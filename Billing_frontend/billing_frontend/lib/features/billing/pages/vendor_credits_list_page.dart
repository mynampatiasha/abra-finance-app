// ============================================================================
// VENDOR CREDITS LIST PAGE
// ============================================================================
// File: lib/screens/billing/pages/vendor_credits_list_page.dart
// Navy blue gradient theme | Fully responsive | Import/Export | Filters
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/vendor_credit_service.dart';
import '../app_top_bar.dart';
import 'new_vendor_credit.dart';
import 'vendor_credit_detail.dart';

// Navy blue gradient colors
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class VendorCreditsListPage extends StatefulWidget {
  const VendorCreditsListPage({Key? key}) : super(key: key);

  @override
  State<VendorCreditsListPage> createState() => _VendorCreditsListPageState();
}

class _VendorCreditsListPageState extends State<VendorCreditsListPage> {
  List<VendorCredit> _credits = [];
  VendorCreditStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  String _selectedStatus = 'All';
  final List<String> _statusFilters = ['All', 'OPEN', 'PARTIALLY_APPLIED', 'CLOSED', 'VOID'];

  DateTime? _fromDate;
  DateTime? _toDate;
  String _dateFilterType = 'All';
  DateTime? _particularDate;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCredits = 0;
  final int _perPage = 20;

  final Set<String> _selected = {};
  bool _selectAll = false;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // DATA
  // -----------------------------------------------------------------------

  Future<void> _load() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      String? from, to;
      if (_dateFilterType == 'Within Date Range') {
        from = _fromDate?.toIso8601String();
        to = _toDate?.toIso8601String();
      } else if (_dateFilterType == 'Particular Date') {
        from = _particularDate?.toIso8601String();
        to = _particularDate?.toIso8601String();
      } else if (_fromDate != null && _toDate != null) {
        from = _fromDate?.toIso8601String();
        to = _toDate?.toIso8601String();
      }

      final res = await VendorCreditService.getVendorCredits(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage,
        limit: _perPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: from,
        toDate: to,
      );
      setState(() {
        _credits = res.credits;
        _totalPages = res.pagination.pages;
        _totalCredits = res.pagination.total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await VendorCreditService.getStats();
      setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), _loadStats()]);
    _showSuccess('Refreshed successfully');
  }

  // -----------------------------------------------------------------------
  // FILTER DIALOG
  // -----------------------------------------------------------------------

  void _showFilterDialog() {
    DateTime? tFrom = _fromDate, tTo = _toDate, tPart = _particularDate;
    String tType = _dateFilterType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Filter by Date', style: TextStyle(color: _navyDark)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter Type', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: tType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All Dates')),
                        DropdownMenuItem(value: 'Within Date Range', child: Text('Within Date Range')),
                        DropdownMenuItem(value: 'Particular Date', child: Text('Particular Date')),
                        DropdownMenuItem(value: 'Today', child: Text('Today')),
                        DropdownMenuItem(value: 'This Week', child: Text('This Week')),
                        DropdownMenuItem(value: 'This Month', child: Text('This Month')),
                        DropdownMenuItem(value: 'Last Month', child: Text('Last Month')),
                        DropdownMenuItem(value: 'This Year', child: Text('This Year')),
                      ],
                      onChanged: (v) {
                        setS(() {
                          tType = v ?? 'All';
                          final now = DateTime.now();
                          if (v == 'Today') { tFrom = now; tTo = now; }
                          else if (v == 'This Week') {
                            tFrom = now.subtract(Duration(days: now.weekday - 1));
                            tTo = now.add(Duration(days: 7 - now.weekday));
                          } else if (v == 'This Month') {
                            tFrom = DateTime(now.year, now.month, 1);
                            tTo = DateTime(now.year, now.month + 1, 0);
                          } else if (v == 'Last Month') {
                            tFrom = DateTime(now.year, now.month - 1, 1);
                            tTo = DateTime(now.year, now.month, 0);
                          } else if (v == 'This Year') {
                            tFrom = DateTime(now.year, 1, 1);
                            tTo = DateTime(now.year, 12, 31);
                          } else if (v == 'All') {
                            tFrom = null; tTo = null; tPart = null;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (tType == 'Within Date Range') ...[
                    _datePicker(ctx, 'From Date', tFrom, (d) => setS(() => tFrom = d)),
                    const SizedBox(height: 16),
                    _datePicker(ctx, 'To Date', tTo, (d) => setS(() => tTo = d)),
                  ],
                  if (tType == 'Particular Date')
                    _datePicker(ctx, 'Select Date', tPart, (d) => setS(() => tPart = d)),
                  if (tType != 'All' && tType != 'Within Date Range' && tType != 'Particular Date' && tFrom != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _navyAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _navyAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        'From ${DateFormat('dd/MM/yyyy').format(tFrom!)} to ${DateFormat('dd/MM/yyyy').format(tTo!)}',
                        style: TextStyle(fontSize: 12, color: _navyAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setS(() { tFrom = null; tTo = null; tPart = null; tType = 'All'; }),
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _dateFilterType = tType;
                  _fromDate = tFrom;
                  _toDate = tTo;
                  _particularDate = tPart;
                  _currentPage = 1;
                });
                Navigator.pop(ctx);
                _load();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _navyAccent, foregroundColor: Colors.white),
              child: const Text('Apply Filter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _datePicker(BuildContext ctx, String label, DateTime? value, Function(DateTime) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) onPick(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 18, color: _navyAccent),
              const SizedBox(width: 8),
              Text(
                value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Select date',
                style: TextStyle(color: value != null ? _navyDark : Colors.grey[600]),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  bool get _hasFilters => _dateFilterType != 'All' || _selectedStatus != 'All';

  void _clearFilters() {
    setState(() {
      _fromDate = null; _toDate = null; _particularDate = null;
      _dateFilterType = 'All'; _selectedStatus = 'All'; _currentPage = 1;
    });
    _load();
  }

  // -----------------------------------------------------------------------
  // IMPORT
  // -----------------------------------------------------------------------

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (_) => _ImportDialog(
        onComplete: () { _refresh(); _showSuccess('Import completed!'); },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // EXPORT
  // -----------------------------------------------------------------------

  Future<void> _export() async {
    try {
      _showSuccess('Preparing export...');
      final all = await VendorCreditService.getAllForExport(
          status: _selectedStatus == 'All' ? null : _selectedStatus);
      if (all.isEmpty) { _showError('No data to export'); return; }

      final data = [
        ['Credit #', 'Vendor Name', 'Vendor Email', 'Credit Date', 'Bill Reference',
          'Reason', 'Status', 'Sub Total', 'CGST', 'SGST', 'TDS', 'TCS',
          'Total Amount', 'Applied Amount', 'Balance Amount', 'Notes'],
        ...all.map((c) => [
          c.creditNumber, c.vendorName, c.vendorEmail ?? '',
          DateFormat('dd/MM/yyyy').format(c.creditDate),
          c.billNumber ?? '', c.reason, c.status,
          c.subTotal.toStringAsFixed(2), c.cgst.toStringAsFixed(2),
          c.sgst.toStringAsFixed(2), c.tdsAmount.toStringAsFixed(2),
          c.tcsAmount.toStringAsFixed(2), c.totalAmount.toStringAsFixed(2),
          c.appliedAmount.toStringAsFixed(2), c.balanceAmount.toStringAsFixed(2),
          c.notes ?? '',
        ]),
      ];

      await ExportHelper.exportToExcel(data: data, filename: 'vendor_credits');
      _showSuccess('✅ Excel downloaded with ${all.length} records!');
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  // -----------------------------------------------------------------------
  // ACTIONS
  // -----------------------------------------------------------------------

  Future<void> _voidCredit(VendorCredit c) async {
    final ok = await _confirm('Void Credit',
        'Are you sure you want to void ${c.creditNumber}? This cannot be undone.', 'Void', Colors.orange);
    if (ok == true) {
      try {
        await VendorCreditService.voidVendorCredit(c.id);
        _showSuccess('Credit voided');
        _refresh();
      } catch (e) { _showError('Failed: $e'); }
    }
  }

  Future<void> _deleteCredit(VendorCredit c) async {
    final ok = await _confirm('Delete Credit',
        'Are you sure you want to delete ${c.creditNumber}?', 'Delete', Colors.red);
    if (ok == true) {
      try {
        await VendorCreditService.deleteVendorCredit(c.id);
        _showSuccess('Deleted');
        _refresh();
      } catch (e) { _showError('Failed: $e'); }
    }
  }

  void _viewProcess() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.88,
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_navyDark, _navyMid, _navyLight],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Vendor Credit Lifecycle Process',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          panEnabled: true,
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Image.asset(
                              'assets/vendor_credit.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _buildFallbackDiagram(),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: Colors.grey[100],
                        child: Text('Tip: Pinch to zoom, drag to pan',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 30, right: 30,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackDiagram() {
    final stages = [
      {'label': 'Credit\nCreated', 'color': Colors.blue, 'icon': Icons.add_circle},
      {'label': 'OPEN', 'color': Colors.orange, 'icon': Icons.pending},
      {'label': 'Partially\nApplied', 'color': Colors.purple, 'icon': Icons.incomplete_circle},
      {'label': 'CLOSED', 'color': Colors.green, 'icon': Icons.check_circle},
    ];

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Vendor Credit Flow', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _navyDark)),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              for (int i = 0; i < stages.length; i++) ...[
                Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (stages[i]['color'] as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: stages[i]['color'] as Color, width: 2),
                    ),
                    child: Column(children: [
                      Icon(stages[i]['icon'] as IconData, color: stages[i]['color'] as Color, size: 32),
                      const SizedBox(height: 6),
                      Text(stages[i]['label'] as String,
                          style: TextStyle(color: stages[i]['color'] as Color, fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center),
                    ]),
                  ),
                ]),
                if (i < stages.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 24),
                    child: Icon(Icons.arrow_forward, color: Colors.grey),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _navyAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _navyAccent.withOpacity(0.3)),
            ),
            child: const Text(
              'Credit Created → OPEN → Apply to Bill or Refund\n→ Partially Applied (if partial) → CLOSED (when fully used)\nCan be VOID at any stage',
              style: TextStyle(fontSize: 13, color: _navyMid),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String title, String content, String label, Color color) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            child: Text(label),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // SNACKBARS
  // -----------------------------------------------------------------------

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  // -----------------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Vendor Credits'),
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopBar(),
            if (_stats != null) _buildStats(),
            _isLoading
                ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator()))
                : _errorMessage != null
                    ? SizedBox(height: 400, child: _buildError())
                    : _credits.isEmpty
                        ? SizedBox(height: 400, child: _buildEmpty())
                        : _buildTable(),
            if (!_isLoading && _credits.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // TOP BAR
  // -----------------------------------------------------------------------

  Widget _buildTopBar() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 700;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: Colors.white,
        child: Row(
          children: [
            // Status dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: _selectedStatus,
                underline: const SizedBox(),
                items: _statusFilters.map((s) {
                  String label;
                  if (s == 'All') label = isWide ? 'All Credits' : 'All';
                  else if (s == 'PARTIALLY_APPLIED') label = isWide ? 'Partial' : 'Part.';
                  else label = s[0] + s.substring(1).toLowerCase();
                  return DropdownMenuItem(
                    value: s,
                    child: Text(label, style: TextStyle(
                      fontSize: isWide ? 16 : 14,
                      fontWeight: FontWeight.w600,
                    )),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _load(); }
                },
              ),
            ),
            const SizedBox(width: 8),
            // Search — flexible width, shrinks on small screens
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: isWide ? 'Search credit#, vendor...' : 'Search...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  isDense: true,
                ),
                onChanged: (v) { setState(() => _searchQuery = v); _load(); },
              ),
            ),
            const SizedBox(width: 6),
            // Filter icon with active dot
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: _showFilterDialog,
                  tooltip: 'Filter',
                  style: IconButton.styleFrom(
                    backgroundColor: _hasFilters ? _navyAccent.withOpacity(0.15) : Colors.grey[200],
                    padding: const EdgeInsets.all(8),
                  ),
                ),
                if (_hasFilters)
                  Positioned(right: 6, top: 6,
                    child: Container(width: 7, height: 7,
                        decoration: const BoxDecoration(color: _navyAccent, shape: BoxShape.circle))),
              ],
            ),
            if (_hasFilters)
              IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                onPressed: _clearFilters,
                tooltip: 'Clear filters',
                style: IconButton.styleFrom(padding: const EdgeInsets.all(6)),
              ),
            // Refresh
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _isLoading ? null : _refresh,
              tooltip: 'Refresh',
              style: IconButton.styleFrom(backgroundColor: Colors.grey[200], padding: const EdgeInsets.all(8)),
            ),
            // View Process
            IconButton(
              icon: const Icon(Icons.account_tree, size: 20, color: _navyAccent),
              onPressed: _viewProcess,
              tooltip: 'View Process',
              style: IconButton.styleFrom(
                  backgroundColor: _navyAccent.withOpacity(0.1), padding: const EdgeInsets.all(8)),
            ),
            const SizedBox(width: 4),
            _actionBtn(isWide ? 'Import' : 'Import', Icons.upload_file, const Color(0xFF9B59B6), _showImportDialog, compact: !isWide),
            const SizedBox(width: 6),
            _actionBtn(isWide ? 'Export' : 'Export', Icons.file_download, const Color(0xFF27AE60),
                _isLoading ? null : _export, compact: !isWide),
            const SizedBox(width: 6),
            _actionBtn(isWide ? 'New Vendor Credit' : 'New', Icons.add, _navyAccent, () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewVendorCreditScreen()),
              );
              if (result == true) _refresh();
            }, compact: !isWide),
          ],
        ),
      );
    });
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback? onTap, {bool compact = false}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: compact ? 14 : 16),
      label: Text(label, style: TextStyle(fontSize: compact ? 14 : 15)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 8 : 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }


  // -----------------------------------------------------------------------
  // STATS CARDS
  // -----------------------------------------------------------------------

  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: LayoutBuilder(builder: (context, constraints) {
        final cards = [
          _statCard('Total Credits', _stats!.totalCredits.toString(), Icons.receipt, Colors.blue),
          _statCard('Total Amount', '₹${_stats!.totalCreditAmount.toStringAsFixed(0)}', Icons.account_balance_wallet, _navyAccent),
          _statCard('Open', _stats!.openCredits.toString(), Icons.pending, Colors.orange),
          _statCard('Partial', _stats!.partiallyApplied.toString(), Icons.incomplete_circle, Colors.purple),
          _statCard('Balance', '₹${_stats!.totalBalance.toStringAsFixed(0)}', Icons.savings, Colors.green),
        ];

        // Always single row — cards shrink proportionally on small screens
        return Row(
          children: cards.expand((c) => [Expanded(child: c), const SizedBox(width: 8)]).toList()
            ..removeLast(),
        );
      }),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return LayoutBuilder(builder: (context, constraints) {
      final isCompact = constraints.maxWidth < 100;
      return Container(
        padding: EdgeInsets.all(isCompact ? 8 : 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.08), color.withOpacity(0.15)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: isCompact ? 16 : 20, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(label,
                    style: TextStyle(fontSize: isCompact ? 11 : 13, color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
              style: TextStyle(
                fontSize: isCompact ? 15 : 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      );
    });
  }

  // -----------------------------------------------------------------------
  // TABLE
  // -----------------------------------------------------------------------

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  headingRowHeight: 56,
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 74,
                  dataTextStyle: const TextStyle(fontSize: 15),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) return _navyAccent.withOpacity(0.05);
                    return null;
                  }),
                  dividerThickness: 1,
                  columnSpacing: 18,
                  horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36,
                      child: Checkbox(
                        value: _selectAll,
                        fillColor: WidgetStateProperty.all(Colors.white),
                        checkColor: _navyDark,
                        onChanged: (v) {
                          setState(() {
                            _selectAll = v ?? false;
                            if (_selectAll) _selected.addAll(_credits.map((c) => c.id));
                            else _selected.clear();
                          });
                        },
                      ),
                    )),
                    const DataColumn(label: SizedBox(width: 130, child: Text('Credit #'))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('Vendor'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('Date'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('Bill Reference'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('Status'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('Total Amount'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('Applied'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('Balance'))),
                    const DataColumn(label: SizedBox(width: 80, child: Text('Actions'))),
                  ],
                  rows: _credits.map((c) => _buildRow(c)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(VendorCredit c) {
    final isSel = _selected.contains(c.id);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((states) {
        if (isSel) return _navyAccent.withOpacity(0.06);
        if (states.contains(WidgetState.hovered)) return _navyAccent.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(Checkbox(
          value: isSel,
          onChanged: (_) {
            setState(() {
              if (isSel) { _selected.remove(c.id); _selectAll = false; }
              else { _selected.add(c.id); if (_selected.length == _credits.length) _selectAll = true; }
            });
          },
        )),
        DataCell(SizedBox(
          width: 130,
          child: InkWell(
            onTap: () => _openDetail(c),
            child: Text(c.creditNumber,
                style: const TextStyle(
                    color: _navyAccent, fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline),
                overflow: TextOverflow.ellipsis),
          ),
        )),
        DataCell(SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(c.vendorName, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              if (c.vendorEmail != null)
                Text(c.vendorEmail!, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ),
        )),
        DataCell(SizedBox(
          width: 110,
          child: Text(DateFormat('dd MMM yyyy').format(c.creditDate)),
        )),
        DataCell(SizedBox(
          width: 120,
          child: c.billNumber != null
              ? Text(c.billNumber!, style: const TextStyle(color: _navyAccent), overflow: TextOverflow.ellipsis)
              : Text('—', style: TextStyle(color: Colors.grey[500])),
        )),
        DataCell(SizedBox(width: 100, child: _statusBadge(c.status))),
        DataCell(SizedBox(
          width: 110,
          child: Text('₹${c.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right),
        )),
        DataCell(SizedBox(
          width: 110,
          child: Text('₹${c.appliedAmount.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500), textAlign: TextAlign.right),
        )),
        DataCell(SizedBox(
          width: 110,
          child: Text('₹${c.balanceAmount.toStringAsFixed(2)}',
              style: TextStyle(
                  color: c.balanceAmount > 0 ? _navyAccent : Colors.grey,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.right),
        )),
        DataCell(SizedBox(
          width: 80,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) async {
              switch (v) {
                case 'view': _openDetail(c); break;
                case 'edit':
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewVendorCreditScreen(creditId: c.id)));
                  if (r == true) _refresh();
                  break;
                case 'void': await _voidCredit(c); break;
                case 'delete': await _deleteCredit(c); break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'view',
                child: ListTile(leading: Icon(Icons.visibility, size: 17, color: _navyAccent),
                    title: Text('View Details'), contentPadding: EdgeInsets.zero)),
              if (c.status != 'VOID' && c.status != 'CLOSED')
                const PopupMenuItem(value: 'edit',
                  child: ListTile(leading: Icon(Icons.edit, size: 17),
                      title: Text('Edit'), contentPadding: EdgeInsets.zero)),
              if (c.status == 'OPEN' || c.status == 'PARTIALLY_APPLIED')
                const PopupMenuItem(value: 'void',
                  child: ListTile(leading: Icon(Icons.block, size: 17, color: Colors.orange),
                      title: Text('Void', style: TextStyle(color: Colors.orange)),
                      contentPadding: EdgeInsets.zero)),
              if (c.status != 'CLOSED')
                const PopupMenuItem(value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete, size: 17, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero)),
            ],
          ),
        )),
      ],
    );
  }

  void _openDetail(VendorCredit c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorCreditDetailPage(creditId: c.id)),
    ).then((result) { if (result == true) _refresh(); });
  }

  Widget _statusBadge(String status) {
    Color bg, fg;
    switch (status) {
      case 'OPEN': bg = Colors.orange[100]!; fg = Colors.orange[800]!; break;
      case 'PARTIALLY_APPLIED': bg = Colors.purple[100]!; fg = Colors.purple[800]!; break;
      case 'CLOSED': bg = Colors.green[100]!; fg = Colors.green[800]!; break;
      case 'VOID': bg = Colors.grey[200]!; fg = Colors.grey[700]!; break;
      default: bg = Colors.blue[100]!; fg = Colors.blue[800]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
          textAlign: TextAlign.center),
    );
  }

  // -----------------------------------------------------------------------
  // PAGINATION
  // -----------------------------------------------------------------------

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 500;
        return isWide
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Showing ${(_currentPage - 1) * _perPage + 1}–${(_currentPage * _perPage).clamp(0, _totalCredits)} of $_totalCredits',
                      style: TextStyle(color: Colors.grey[700])),
                  _pageControls(),
                ],
              )
            : Column(children: [
                Text('Showing ${(_currentPage - 1) * _perPage + 1}–${(_currentPage * _perPage).clamp(0, _totalCredits)} of $_totalCredits',
                    style: TextStyle(color: Colors.grey[700])),
                const SizedBox(height: 8),
                _pageControls(),
              ]);
      }),
    );
  }

  Widget _pageControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _load(); } : null,
        ),
        ...List.generate(_totalPages.clamp(0, 5), (i) {
          final p = i + 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () { setState(() => _currentPage = p); _load(); },
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  gradient: _currentPage == p
                      ? const LinearGradient(colors: [_navyDark, _navyAccent])
                      : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text('$p', style: TextStyle(
                  color: _currentPage == p ? Colors.white : Colors.grey[700],
                  fontWeight: _currentPage == p ? FontWeight.bold : FontWeight.normal,
                )),
              ),
            ),
          );
        }),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _currentPage < _totalPages ? () { setState(() => _currentPage++); _load(); } : null,
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // EMPTY / ERROR
  // -----------------------------------------------------------------------

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.credit_score, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No vendor credits found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text('Create a vendor credit for returned goods or overcharges',
              style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final r = await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const NewVendorCreditScreen()));
              if (r == true) _refresh();
            },
            icon: const Icon(Icons.add),
            label: const Text('Create Vendor Credit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text('Error Loading Credits',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_errorMessage ?? 'Unknown error',
                style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// IMPORT DIALOG
// ============================================================================

class _ImportDialog extends StatefulWidget {
  final VoidCallback onComplete;
  const _ImportDialog({required this.onComplete});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _downloading = false;
  bool _uploading = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = [
        ['Credit Date* (YYYY-MM-DD)', 'Vendor Name*', 'Vendor Email', 'Bill Number (Optional)',
          'Reason*', 'Item Description*', 'Quantity*', 'Rate*', 'GST Rate (%)',
          'TDS Rate (%)', 'TCS Rate (%)', 'Notes'],
        ['2024-01-15', 'ABC Vendor', 'abc@vendor.com', 'BILL-2024-001',
          'Goods Returned', 'Office Chair (Returned)', '2', '5000', '18', '0', '0', 'Defective item returned'],
        ['2024-01-20', 'XYZ Supplier', 'xyz@supplier.com', '',
          'Overcharged by Vendor', 'Overcharge Adjustment', '1', '2500', '5', '0', '0', 'Vendor overcharged for services'],
        ['--- DELETE THIS ROW ---', 'Reason options: Goods Returned / Overcharged by Vendor / Quality Issue / Advance Payment Excess / Discount After Billing / Duplicate Invoice / Service Not Delivered / Other',
          '', '', '', '', '', '', '', '', '', ''],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'vendor_credits_import_template');
      setState(() => _downloading = false);
      _snack('Template downloaded!', Colors.green);
    } catch (e) {
      setState(() => _downloading = false);
      _snack('Failed: $e', Colors.red);
    }
  }

  Future<void> _upload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      final bytes = file.bytes;
      if (bytes == null) throw Exception('Could not read file');

      List<List<dynamic>> rows;
      final ext = file.extension?.toLowerCase() ?? '';
      rows = ext == 'csv' ? _parseCSV(bytes) : _parseExcel(bytes);

      if (rows.length < 2) throw Exception('File needs at least one data row');

      final toImport = <Map<String, dynamic>>[];
      final errors = <String>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _str(row, 0).isEmpty || _str(row, 0).startsWith('---')) continue;
        try {
          final creditDate = _str(row, 0);
          final vendorName = _str(row, 1);
          final reason = _str(row, 4);
          final itemDesc = _str(row, 5);
          final qty = double.tryParse(_str(row, 6)) ?? 0;
          final rate = double.tryParse(_str(row, 7)) ?? 0;

          if (creditDate.isEmpty) throw Exception('Credit Date required');
          DateTime.parse(creditDate);
          if (vendorName.isEmpty) throw Exception('Vendor Name required');
          if (reason.isEmpty) throw Exception('Reason required');
          if (itemDesc.isEmpty) throw Exception('Item Description required');
          if (qty <= 0) throw Exception('Quantity must be > 0');
          if (rate <= 0) throw Exception('Rate must be > 0');

          final gst = double.tryParse(_str(row, 8)) ?? 18.0;
          final amount = qty * rate;
          final gstAmt = amount * gst / 100;

          toImport.add({
            'creditDate': creditDate,
            'vendorId': 'import_${vendorName.toLowerCase().replaceAll(' ', '_')}',
            'vendorName': vendorName,
            'vendorEmail': _str(row, 2),
            'billNumber': _str(row, 3).isNotEmpty ? _str(row, 3) : null,
            'reason': reason,
            'items': [{'itemDetails': itemDesc, 'quantity': qty, 'rate': rate, 'amount': amount,
              'discount': 0, 'discountType': 'percentage'}],
            'gstRate': gst,
            'tdsRate': double.tryParse(_str(row, 9)) ?? 0,
            'tcsRate': double.tryParse(_str(row, 10)) ?? 0,
            'subTotal': amount,
            'cgst': gstAmt / 2,
            'sgst': gstAmt / 2,
            'totalAmount': amount + gstAmt,
            'notes': _str(row, 11),
            'status': 'OPEN',
          });
        } catch (e) {
          errors.add('Row ${i + 1}: $e');
        }
      }

      if (toImport.isEmpty) throw Exception('No valid data found');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirm Import'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${toImport.length} credit(s) ready to import',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('${errors.length} row(s) skipped', style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 130),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(6)),
                  child: SingleChildScrollView(
                    child: Text(errors.join('\n'), style: const TextStyle(fontSize: 11, color: Colors.red)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _navyAccent),
              child: const Text('Import', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) { setState(() { _uploading = false; _fileName = null; }); return; }

      final res = await VendorCreditService.bulkImport(toImport);
      setState(() {
        _uploading = false;
        _results = {
          'total': res['data']['totalProcessed'],
          'success': res['data']['successCount'],
          'failed': res['data']['failedCount'],
          'errors': res['data']['errors'] ?? [],
        };
      });

      if ((res['data']['successCount'] ?? 0) > 0) widget.onComplete();
    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _snack('Import failed: $e', Colors.red);
    }
  }

  String _str(List<dynamic> row, int i, [String d = '']) {
    if (i >= row.length || row[i] == null) return d;
    return row[i].toString().trim();
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex = excel_pkg.Excel.decodeBytes(bytes);
    final sheet = ex.tables.keys.first;
    return (ex.tables[sheet]?.rows ?? []).map((row) => row.map((c) {
      if (c?.value == null) return '';
      if (c!.value is excel_pkg.TextCellValue) return (c.value as excel_pkg.TextCellValue).value;
      return c.value;
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true)
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map((l) {
          final fields = <String>[];
          final buf = StringBuffer();
          bool inQ = false;
          for (int i = 0; i < l.length; i++) {
            final c = l[i];
            if (c == '"') {
              if (inQ && i + 1 < l.length && l[i + 1] == '"') { buf.write('"'); i++; }
              else inQ = !inQ;
            } else if (c == ',' && !inQ) { fields.add(buf.toString()); buf.clear(); }
            else buf.write(c);
          }
          fields.add(buf.toString());
          return fields.map((f) => f.startsWith('"') && f.endsWith('"') ? f.substring(1, f.length - 1) : f).toList();
        }).toList();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width > 600
            ? 560
            : MediaQuery.of(context).size.width * 0.92,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.upload_file, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Bulk Import Vendor Credits',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: _navyDark)),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(height: 28),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _navyAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _navyAccent.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.info_outline, color: _navyAccent, size: 18),
                      const SizedBox(width: 8),
                      Text('How to Import', style: TextStyle(fontWeight: FontWeight.w600, color: _navyMid)),
                    ]),
                    const SizedBox(height: 8),
                    const Text('1. Download the sample template\n'
                        '2. Fill in your vendor credit data\n'
                        '3. Delete the instructions row before uploading\n'
                        '4. Upload completed .xlsx or .csv file',
                        style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _downloading || _uploading ? null : _downloadTemplate,
                  icon: _downloading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download),
                  label: Text(_downloading ? 'Downloading...' : 'Download Sample Template'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _downloading || _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _navyMid))
                      : const Icon(Icons.upload_file),
                  label: Text(_uploading ? 'Processing...' : 'Upload Excel / CSV File'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navyMid,
                    side: const BorderSide(color: _navyMid),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_fileName != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_fileName!,
                        style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600))),
                  ]),
                ),
              ],
              if (_results != null) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text('Import Results',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(children: [
                    _resultRow('Total Processed', '${_results!['total']}', Colors.blue),
                    const SizedBox(height: 6),
                    _resultRow('Successfully Imported', '${_results!['success']}', Colors.green),
                    const SizedBox(height: 6),
                    _resultRow('Failed', '${_results!['failed']}', Colors.red),
                    if ((_results!['errors'] as List).isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(6)),
                        child: SingleChildScrollView(
                          child: Text((_results!['errors'] as List).join('\n'),
                              style: const TextStyle(fontSize: 11, color: Colors.red)),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navyAccent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}