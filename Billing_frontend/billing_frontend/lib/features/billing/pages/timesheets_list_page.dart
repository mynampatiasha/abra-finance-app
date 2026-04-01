// ============================================================================
// TIMESHEETS LIST PAGE — Time Tracking Module
// ============================================================================
// File: lib/screens/billing/pages/timesheets_list_page.dart
// UI Pattern: exact recurring_bills_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/timesheet_service.dart';
import '../../../../core/services/project_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_time_entry.dart';

const Color _tsNavy   = Color(0xFF1e3a8a);
const Color _tsGreen  = Color(0xFF27AE60);
const Color _tsBlue   = Color(0xFF2980B9);
const Color _tsOrange = Color(0xFFE67E22);
const Color _tsRed    = Color(0xFFE74C3C);
const Color _tsPurple = Color(0xFF9B59B6);
const Color _tsTeal   = Color(0xFF00897B);

class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({required this.label, required this.value, required this.icon, required this.color, required this.gradientColors});
}

class TimesheetsListPage extends StatefulWidget {
  const TimesheetsListPage({Key? key}) : super(key: key);
  @override
  State<TimesheetsListPage> createState() => _TimesheetsListPageState();
}

class _TimesheetsListPageState extends State<TimesheetsListPage> {
  List<TimeEntry>   _timesheets = [];
  TimesheetStats?   _stats;
  List<Project>     _allProjects = [];
  bool _isLoading = true;
  String? _errorMessage;

  String _selectedStatus    = 'All';
  String _selectedProjectId = 'All';
  String _selectedBillable  = 'All';
  DateTime? _fromDate, _toDate;
  String _dateFilterType    = 'All';

  final List<String> _statusFilters = ['All', 'Unbilled', 'Approved', 'Billed', 'Rejected'];

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  int _currentPage = 1, _totalPages = 1, _totalEntries = 0;
  final int _perPage = 20;

  final Set<String> _selectedEntries = {};
  bool _selectAll = false;

  final ScrollController _tableHScroll = ScrollController();
  final ScrollController _statsHScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _load();
    _loadStats();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScroll.dispose();
    _statsHScroll.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final resp = await ProjectService.getProjects(limit: 200);
      if (mounted) setState(() => _allProjects = resp.projects);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      String? fromStr, toStr;
      if (_dateFilterType != 'All') { fromStr = _fromDate?.toIso8601String(); toStr = _toDate?.toIso8601String(); }
      final resp = await TimesheetService.getTimesheets(
        status:    _selectedStatus    == 'All' ? null : _selectedStatus,
        projectId: _selectedProjectId == 'All' ? null : _selectedProjectId,
        isBillable: _selectedBillable == 'All' ? null : _selectedBillable == 'Billable',
        search:    _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate:  fromStr, toDate: toStr,
        page: _currentPage, limit: _perPage,
      );
      setState(() {
        _timesheets   = resp.timesheets;
        _totalPages   = resp.pagination.pages;
        _totalEntries = resp.pagination.total;
        _isLoading    = false;
        _selectedEntries.clear();
        _selectAll = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try { final s = await TimesheetService.getStats(); setState(() => _stats = s); } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), _loadStats()]);
    _showSuccess('Data refreshed');
  }

  bool get _hasFilters => _dateFilterType != 'All' || _selectedStatus != 'All' || _selectedProjectId != 'All' || _selectedBillable != 'All';

  void _clearFilters() {
    setState(() { _fromDate = null; _toDate = null; _dateFilterType = 'All'; _selectedStatus = 'All'; _selectedProjectId = 'All'; _selectedBillable = 'All'; _currentPage = 1; });
    _searchCtrl.clear();
    _load();
  }

  // ── actions ────────────────────────────────────────────────────────────────
  void _openNew() async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewTimeEntryScreen()));
    if (ok == true) _refresh();
  }

  void _openEdit(TimeEntry e) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewTimeEntryScreen(entryId: e.id)));
    if (ok == true) _refresh();
  }

  Future<void> _approve(TimeEntry e) async {
    try { await TimesheetService.approveEntry(e.id); _showSuccess('Entry approved'); _refresh(); }
    catch (err) { _showError('Failed: $err'); }
  }

  Future<void> _reject(TimeEntry e) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Reject Time Entry', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Reject entry for "${e.projectName}" (${e.hours.toStringAsFixed(1)} hrs)?'),
        const SizedBox(height: 12),
        TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()), maxLines: 2),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _tsRed, foregroundColor: Colors.white), child: const Text('Reject')),
      ],
    ));
    if (ok != true) return;
    try { await TimesheetService.rejectEntry(e.id, reason: reasonCtrl.text); _showSuccess('Entry rejected'); _refresh(); }
    catch (err) { _showError('Failed: $err'); }
  }

  Future<void> _delete(TimeEntry e) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Entry?', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text('Delete time entry for "${e.projectName}" (${e.hours.toStringAsFixed(1)} hrs)?\n\nThis cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _tsRed, foregroundColor: Colors.white), child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try { await TimesheetService.deleteEntry(e.id); _showSuccess('Entry deleted'); _refresh(); }
    catch (err) { _showError('Failed: $err'); }
  }

  void _raiseTicket(TimeEntry e) {
    showDialog(context: context, barrierDismissible: true,
        builder: (_) => _RaiseTicketOverlay(entry: e, onTicketRaised: _showSuccess, onError: _showError));
  }

  // ── bulk actions ───────────────────────────────────────────────────────────
  Future<void> _bulkApprove() async {
    if (_selectedEntries.isEmpty) { _showError('Select entries to approve'); return; }
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Bulk Approve?', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text('Approve ${_selectedEntries.length} selected time entr${_selectedEntries.length == 1 ? 'y' : 'ies'}?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _tsGreen, foregroundColor: Colors.white), child: const Text('Approve All'))],
    ));
    if (ok != true) return;
    int success = 0;
    for (final id in List.from(_selectedEntries)) { try { await TimesheetService.approveEntry(id); success++; } catch (_) {} }
    _showSuccess('$success entr${success == 1 ? 'y' : 'ies'} approved');
    _refresh();
  }

  // ── export ─────────────────────────────────────────────────────────────────
  Future<void> _exportExcel() async {
    try {
      _showSuccess('Preparing export…');
      final all = await TimesheetService.getAllForExport(
        status:    _selectedStatus    == 'All' ? null : _selectedStatus,
        projectId: _selectedProjectId == 'All' ? null : _selectedProjectId,
      );
      if (all.isEmpty) { _showError('No data to export'); return; }
      final rows = <List<dynamic>>[
        ['Entry#', 'Date', 'Project', 'Task', 'Staff', 'Hours', 'Billable', 'Status', 'Notes', 'Approved By'],
        ...all.map((e) => [
          e.entryNumber,
          DateFormat('dd/MM/yyyy').format(e.date),
          e.projectName, e.taskName, e.userName,
          e.hours.toStringAsFixed(2),
          e.isBillable ? 'Yes' : 'No',
          e.status, e.notes,
          e.approvedBy ?? '',
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'timesheets');
      _showSuccess('✅ Excel downloaded (${all.length} entries)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ─────────────────────────────────────────────────────────────────
  void _handleImport() {
    showDialog(context: context, builder: (_) => _BulkImportTimesheetsDialog(projects: _allProjects, onImportComplete: _refresh));
  }

  // ── filter dialog ──────────────────────────────────────────────────────────
  void _showFilterDialog() {
    DateTime? tFrom = _fromDate, tTo = _toDate;
    String tType = _dateFilterType;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Filter Timesheets', style: TextStyle(color: _tsNavy, fontWeight: FontWeight.bold)),
        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
      ]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Billable', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: DropdownButton<String>(value: _selectedBillable, isExpanded: true, underline: const SizedBox(),
              items: const [DropdownMenuItem(value: 'All', child: Text('All')), DropdownMenuItem(value: 'Billable', child: Text('Billable Only')), DropdownMenuItem(value: 'Non-Billable', child: Text('Non-Billable Only'))],
              onChanged: (v) => setS(() => _selectedBillable = v ?? 'All'))),
        const SizedBox(height: 16),
        const Text('Date Filter', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: DropdownButton<String>(value: tType, isExpanded: true, underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'All',               child: Text('All Dates')),
              DropdownMenuItem(value: 'Today',             child: Text('Today')),
              DropdownMenuItem(value: 'This Week',         child: Text('This Week')),
              DropdownMenuItem(value: 'This Month',        child: Text('This Month')),
              DropdownMenuItem(value: 'Last Month',        child: Text('Last Month')),
              DropdownMenuItem(value: 'Within Date Range', child: Text('Within Date Range')),
              DropdownMenuItem(value: 'Particular Date',   child: Text('Particular Date')),
            ],
            onChanged: (v) { setS(() {
              tType = v ?? 'All'; final now = DateTime.now();
              if (v == 'Today') { tFrom = now; tTo = now; }
              else if (v == 'This Week') { tFrom = now.subtract(Duration(days: now.weekday - 1)); tTo = now.add(Duration(days: 7 - now.weekday)); }
              else if (v == 'This Month') { tFrom = DateTime(now.year, now.month, 1); tTo = DateTime(now.year, now.month + 1, 0); }
              else if (v == 'Last Month') { tFrom = DateTime(now.year, now.month - 1, 1); tTo = DateTime(now.year, now.month, 0); }
              else if (v == 'All') { tFrom = null; tTo = null; }
            }); },
          )),
        if (tType == 'Within Date Range') ...[const SizedBox(height: 10), _datePickerRow(ctx, 'From', tFrom, (d) => setS(() => tFrom = d)), const SizedBox(height: 8), _datePickerRow(ctx, 'To', tTo, (d) => setS(() => tTo = d))],
        if (tType == 'Particular Date') ...[const SizedBox(height: 10), _datePickerRow(ctx, 'Date', tFrom, (d) => setS(() => tFrom = d))],
      ]))),
      actions: [
        TextButton(onPressed: () => setS(() { tFrom = null; tTo = null; tType = 'All'; _selectedBillable = 'All'; }), child: const Text('Clear', style: TextStyle(color: _tsRed))),
        ElevatedButton(onPressed: () {
          setState(() { _dateFilterType = tType; _fromDate = tFrom; _toDate = tTo; _currentPage = 1; });
          Navigator.pop(ctx); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: _tsNavy, foregroundColor: Colors.white), child: const Text('Apply')),
      ],
    )));
  }

  Widget _datePickerRow(BuildContext ctx, String label, DateTime? value, Function(DateTime) onPick) {
    return Row(children: [
      Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
      Expanded(child: InkWell(onTap: () async {
        final d = await showDatePicker(context: ctx, initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
        if (d != null) onPick(d);
      }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: Text(value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Select', style: TextStyle(color: value != null ? _tsNavy : Colors.grey[500]))))),
    ]);
  }

  // ── snackbars ──────────────────────────────────────────────────────────────
  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
        backgroundColor: _tsGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 3)));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
        backgroundColor: _tsRed, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 4)));
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Timesheet'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(child: Column(children: [
        _buildTopBar(),
        _buildStatsCards(),
        _buildBulkBar(),
        _isLoading
            ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _tsNavy)))
            : _errorMessage != null
                ? SizedBox(height: 400, child: _buildErrorState())
                : _timesheets.isEmpty
                    ? SizedBox(height: 400, child: _buildEmptyState())
                    : _buildTable(),
        if (!_isLoading && _timesheets.isNotEmpty) _buildPagination(),
      ])),
    );
  }

  Widget _buildTopBar() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _statusDrop(), const SizedBox(width: 8), _projectDrop(), const SizedBox(width: 10),
    _searchField(width: 220), const SizedBox(width: 8),
    Stack(children: [
      _iconBtn(Icons.filter_list, _showFilterDialog, color: _hasFilters ? _tsNavy : const Color(0xFF7F8C8D), bg: _hasFilters ? _tsNavy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
      if (_hasFilters) Positioned(right: 4, top: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: _tsNavy, shape: BoxShape.circle))),
    ]),
    if (_hasFilters) ...[const SizedBox(width: 4), _iconBtn(Icons.clear, _clearFilters, color: _tsRed, bg: Colors.red[50]!)],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const Spacer(),
    _actionBtn('New Entry', Icons.add_rounded, _tsNavy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _tsPurple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _tsGreen, _timesheets.isEmpty ? null : _exportExcel),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [_statusDrop(), const SizedBox(width: 8), _projectDrop(), const SizedBox(width: 8),
        Expanded(child: _searchField(width: double.infinity)), const SizedBox(width: 6),
        Stack(children: [_iconBtn(Icons.filter_list, _showFilterDialog, color: _hasFilters ? _tsNavy : const Color(0xFF7F8C8D), bg: _hasFilters ? _tsNavy.withOpacity(0.08) : const Color(0xFFF1F1F1)), if (_hasFilters) Positioned(right: 4, top: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: _tsNavy, shape: BoxShape.circle)))]),
        if (_hasFilters) ...[const SizedBox(width: 4), _iconBtn(Icons.clear, _clearFilters, color: _tsRed, bg: Colors.red[50]!)],
        const SizedBox(width: 6), _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh)]),
    const SizedBox(height: 10),
    Row(children: [_actionBtn('New Entry', Icons.add_rounded, _tsNavy, _openNew), const SizedBox(width: 8), _actionBtn('Import', Icons.upload_file_rounded, _tsPurple, _isLoading ? null : _handleImport), const SizedBox(width: 8), _actionBtn('Export', Icons.download_rounded, _tsGreen, _timesheets.isEmpty ? null : _exportExcel)]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [_statusDrop(), const SizedBox(width: 8), Expanded(child: _searchField(width: double.infinity)), const SizedBox(width: 8), _actionBtn('New', Icons.add_rounded, _tsNavy, _openNew)]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [_projectDrop(), const SizedBox(width: 6), Stack(children: [_iconBtn(Icons.filter_list, _showFilterDialog, color: _hasFilters ? _tsNavy : const Color(0xFF7F8C8D)), if (_hasFilters) Positioned(right: 4, top: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: _tsNavy, shape: BoxShape.circle)))]),
        if (_hasFilters) ...[const SizedBox(width: 6), _iconBtn(Icons.clear, _clearFilters, color: _tsRed, bg: Colors.red[50]!)],
        const SizedBox(width: 6), _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
        const SizedBox(width: 6), _compactBtn('Import', _tsPurple, _handleImport), const SizedBox(width: 6), _compactBtn('Export', _tsGreen, _timesheets.isEmpty ? null : _exportExcel)])),
  ]);

  Widget _statusDrop() => Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _selectedStatus, icon: const Icon(Icons.expand_more, size: 18, color: _tsNavy), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tsNavy),
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Status' : s))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _load(); } })));

  Widget _projectDrop() => Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _selectedProjectId, icon: const Icon(Icons.expand_more, size: 18, color: _tsNavy), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tsNavy),
        items: [const DropdownMenuItem(value: 'All', child: Text('All Projects')), ..._allProjects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.projectName, overflow: TextOverflow.ellipsis)))],
        onChanged: (v) { if (v != null) { setState(() { _selectedProjectId = v; _currentPage = 1; }); _load(); } })));

  Widget _searchField({required double width}) {
    final field = TextField(controller: _searchCtrl, style: const TextStyle(fontSize: 14),
      onChanged: (v) { setState(() { _searchQuery = v; _currentPage = 1; }); Future.delayed(const Duration(milliseconds: 500), () { if (_searchQuery == v) _load(); }); },
      decoration: InputDecoration(hintText: 'Search entries…', hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
          suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); setState(() { _searchQuery = ''; _currentPage = 1; }); _load(); }) : null,
          filled: true, fillColor: const Color(0xFFF7F9FC), contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _tsNavy, width: 1.5))));
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
    return Tooltip(message: tooltip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Container(width: 42, height: 42, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))), child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color))));
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, disabledBackgroundColor: bg.withOpacity(0.5), elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) {
    return ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, disabledBackgroundColor: bg.withOpacity(0.5), elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));
  }

  // ── bulk bar ───────────────────────────────────────────────────────────────
  Widget _buildBulkBar() {
    if (_selectedEntries.isEmpty) return const SizedBox.shrink();
    return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), color: _tsNavy.withOpacity(0.08),
      child: Row(children: [
        Text('${_selectedEntries.length} selected', style: const TextStyle(fontWeight: FontWeight.w600, color: _tsNavy)),
        const SizedBox(width: 16),
        ElevatedButton.icon(onPressed: _bulkApprove, icon: const Icon(Icons.check, size: 16), label: const Text('Approve'),
            style: ElevatedButton.styleFrom(backgroundColor: _tsGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
        const Spacer(),
        TextButton(onPressed: () => setState(() { _selectedEntries.clear(); _selectAll = false; }), child: const Text('Deselect All', style: TextStyle(color: _tsNavy))),
      ]));
  }

  // ── stats cards ────────────────────────────────────────────────────────────
  Widget _buildStatsCards() {
    final cards = [
      _StatCardData(label: 'Total Entries', value: (_stats?.total ?? 0).toString(), icon: Icons.list_alt_outlined, color: _tsNavy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Unbilled', value: (_stats?.unbilled ?? 0).toString(), icon: Icons.schedule_outlined, color: _tsOrange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Approved', value: (_stats?.approved ?? 0).toString(), icon: Icons.check_circle_outline, color: _tsGreen, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Billed', value: (_stats?.billed ?? 0).toString(), icon: Icons.receipt_long_outlined, color: _tsTeal, gradientColors: const [Color(0xFF26A69A), Color(0xFF00897B)]),
      _StatCardData(label: 'Total Hours', value: (_stats?.totalHours ?? 0).toStringAsFixed(1) + 'h', icon: Icons.access_time_outlined, color: _tsPurple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
    ];
    return Container(width: double.infinity, color: const Color(0xFFF0F4F8), padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) return SingleChildScrollView(controller: _statsHScroll, scrollDirection: Axis.horizontal, child: Row(children: cards.asMap().entries.map((e) => Container(width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0), child: _statCard(e.value, compact: true))).toList()));
        return Row(children: cards.asMap().entries.map((e) => Expanded(child: Padding(padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0), child: _statCard(e.value, compact: false)))).toList());
      }));
  }

  Widget _statCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), border: Border.all(color: d.color.withOpacity(0.22)), boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))]),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)), child: Icon(d.icon, color: Colors.white, size: 20)), const SizedBox(height: 10), Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color))])
          : Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))]), child: Icon(d.icon, color: Colors.white, size: 24)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 5), Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: d.color))]))]),
    );
  }

  // ── table ──────────────────────────────────────────────────────────────────
  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (context, constraints) => Scrollbar(
        controller: _tableHScroll, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
        child: ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
          child: SingleChildScrollView(controller: _tableHScroll, scrollDirection: Axis.horizontal,
            child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                headingRowHeight: 52, dataRowMinHeight: 60, dataRowMaxHeight: 76,
                dataTextStyle: const TextStyle(fontSize: 13),
                dataRowColor: WidgetStateProperty.resolveWith((s) { if (s.contains(WidgetState.hovered)) return _tsNavy.withOpacity(0.04); return null; }),
                dividerThickness: 1, columnSpacing: 16, horizontalMargin: 16,
                columns: [
                  DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E),
                      onChanged: (v) { setState(() { _selectAll = v ?? false; if (_selectAll) _selectedEntries.addAll(_timesheets.map((e) => e.id)); else _selectedEntries.clear(); }); }))),
                  const DataColumn(label: SizedBox(width: 90,  child: Text('DATE'))),
                  const DataColumn(label: SizedBox(width: 150, child: Text('PROJECT'))),
                  const DataColumn(label: SizedBox(width: 130, child: Text('TASK'))),
                  const DataColumn(label: SizedBox(width: 130, child: Text('STAFF'))),
                  const DataColumn(label: SizedBox(width: 70,  child: Text('HOURS'))),
                  const DataColumn(label: SizedBox(width: 80,  child: Text('BILLABLE'))),
                  const DataColumn(label: SizedBox(width: 110, child: Text('STATUS'))),
                  const DataColumn(label: SizedBox(width: 220, child: Text('ACTIONS'))),
                ],
                rows: _timesheets.map((e) => _buildRow(e)).toList(),
              )))))));
  }

  DataRow _buildRow(TimeEntry e) {
    final isSel = _selectedEntries.contains(e.id);
    final canApprove = e.status == 'Unbilled' || e.status == 'Rejected';
    final canReject  = e.status == 'Unbilled' || e.status == 'Approved';
    return DataRow(selected: isSel,
      color: WidgetStateProperty.resolveWith((s) { if (isSel) return _tsNavy.withOpacity(0.06); if (s.contains(WidgetState.hovered)) return _tsNavy.withOpacity(0.04); return null; }),
      cells: [
        DataCell(Checkbox(value: isSel, onChanged: (_) { setState(() { if (isSel) { _selectedEntries.remove(e.id); _selectAll = false; } else { _selectedEntries.add(e.id); if (_selectedEntries.length == _timesheets.length) _selectAll = true; } }); })),
        DataCell(SizedBox(width: 90, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(DateFormat('dd MMM').format(e.date), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(DateFormat('yyyy').format(e.date), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),
        DataCell(SizedBox(width: 150, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(e.projectName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(e.entryNumber, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),
        DataCell(SizedBox(width: 130, child: Text(e.taskName.isNotEmpty ? e.taskName : '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))),
        DataCell(SizedBox(width: 130, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(e.userName.isNotEmpty ? e.userName : '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          if (e.userEmail.isNotEmpty) Text(e.userEmail, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),
        DataCell(SizedBox(width: 70, child: Text('${e.hours.toStringAsFixed(1)}h', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _tsNavy)))),
        DataCell(SizedBox(width: 80, child: _billableBadge(e.isBillable))),
        DataCell(SizedBox(width: 110, child: _statusBadge(e.status))),
        DataCell(SizedBox(width: 220, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          if (canApprove) ...[_rowBtn(Icons.check_circle_outline, 'Approve', _tsGreen, () => _approve(e)), const SizedBox(width: 4)],
          if (canReject)  ...[_rowBtn(Icons.cancel_outlined, 'Reject', _tsRed, () => _reject(e)), const SizedBox(width: 4)],
          PopupMenuButton<String>(icon: const Icon(Icons.more_vert, size: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('edit',   Icons.edit_outlined,               _tsBlue,   'Edit'),
              _menuItem('ticket', Icons.confirmation_number_outlined, _tsOrange, 'Raise Ticket'),
              _menuItem('delete', Icons.delete_outline,              _tsRed,    'Delete', textColor: _tsRed),
            ],
            onSelected: (v) { switch (v) { case 'edit': _openEdit(e); break; case 'ticket': _raiseTicket(e); break; case 'delete': _delete(e); break; } }),
        ])))),
      ]);
  }

  Widget _rowBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(message: tooltip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.30), width: 1.2)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 3), Text(tooltip, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))]))));
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color iconColor, String label, {Color? textColor}) {
    return PopupMenuItem(value: value, child: ListTile(leading: Icon(icon, size: 17, color: iconColor), title: Text(label, style: TextStyle(color: textColor)), contentPadding: EdgeInsets.zero, dense: true));
  }

  Widget _billableBadge(bool billable) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: billable ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
        child: Text(billable ? 'Bill.' : 'Non-B.', style: TextStyle(color: billable ? const Color(0xFF0369A1) : Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w600)));
  }

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'Unbilled':  [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'Approved':  [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'Billed':    [Color(0xFFE0F2FE), Color(0xFF0369A1)],
      'Rejected':  [Color(0xFFFEE2E2), Color(0xFFDC2626)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)), const SizedBox(width: 5), Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11))]));
  }

  // ── pagination (same as projects_list_page) ────────────────────────────────
  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) { pages = List.generate(_totalPages, (i) => i + 1); }
    else { final start = (_currentPage - 2).clamp(1, _totalPages - 4); pages = List.generate(5, (i) => start + i); }
    return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: LayoutBuilder(builder: (_, c) => Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        Text('Showing ${(_currentPage - 1) * _perPage + 1}–${(_currentPage * _perPage).clamp(0, _totalEntries)} of $_totalEntries', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); _load(); }),
          const SizedBox(width: 4),
          if (pages.first > 1) ...[_pageNumBtn(1), if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400])))],
          ...pages.map((p) => _pageNumBtn(p)),
          if (pages.last < _totalPages) ...[if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))), _pageNumBtn(_totalPages)],
          const SizedBox(width: 4),
          _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _load(); }),
        ]),
      ])));
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(onTap: () { if (!isActive) { setState(() => _currentPage = page); _load(); } },
      child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.symmetric(horizontal: 2), width: 34, height: 34, decoration: BoxDecoration(color: isActive ? _tsNavy : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? _tsNavy : Colors.grey[300]!)),
          child: Center(child: Text('$page', style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.white : Colors.grey[700])))));
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(onTap: enabled ? onTap : null, child: Container(width: 34, height: 34, decoration: BoxDecoration(color: enabled ? Colors.white : Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)), child: Icon(icon, size: 18, color: enabled ? _tsNavy : Colors.grey[300])));
  }

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _tsNavy.withOpacity(0.06), shape: BoxShape.circle), child: Icon(Icons.access_time_outlined, size: 64, color: _tsNavy.withOpacity(0.4))),
      const SizedBox(height: 20), const Text('No Time Entries Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
      Text(_hasFilters ? 'Try adjusting your filters' : 'Log time to start tracking billable hours', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(onPressed: _hasFilters ? _clearFilters : _openNew, icon: Icon(_hasFilters ? Icons.filter_list_off : Icons.add), label: Text(_hasFilters ? 'Clear Filters' : 'Log Time', style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _tsNavy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle), child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20), const Text('Failed to Load Timesheets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center),
      const SizedBox(height: 28), ElevatedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Retry'),
          style: ElevatedButton.styleFrom(backgroundColor: _tsNavy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }
}

// =============================================================================
// RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final TimeEntry entry;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({required this.entry, required this.onTicketRaised, required this.onError});
  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _employees = [], _filtered = [];
  Map<String, dynamic>? _selectedEmp;
  bool _loading = true, _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() { super.initState(); _loadEmployees(); _searchCtrl.addListener(_filter); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() { _employees = List<Map<String, dynamic>>.from(resp['data']); _filtered = _employees; _loading = false; });
    } else { setState(() => _loading = false); widget.onError('Failed to load employees'); }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() { _filtered = q.isEmpty ? _employees : _employees.where((e) => (e['name_parson'] ?? '').toLowerCase().contains(q) || (e['email'] ?? '').toLowerCase().contains(q)).toList(); });
  }

  String _buildMessage() {
    final e = widget.entry;
    return 'Time entry "${e.entryNumber}" for project "${e.projectName}" requires attention.\n\n'
        'Entry Details:\n'
        '• Date: ${DateFormat('dd/MM/yyyy').format(e.date)}\n'
        '• Hours: ${e.hours.toStringAsFixed(2)} hrs\n'
        '• Staff: ${e.userName}\n'
        '• Task: ${e.taskName.isNotEmpty ? e.taskName : "General"}\n'
        '• Billable: ${e.isBillable ? "Yes" : "No"}\n'
        '• Status: ${e.status}\n\n'
        'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(subject: 'Time Entry: ${widget.entry.projectName}', message: _buildMessage(), priority: _priority, timeline: 1440, assignedTo: _selectedEmp!['_id'].toString());
      setState(() => _assigning = false);
      if (resp['success'] == true) { widget.onTicketRaised('Ticket assigned to ${_selectedEmp!['name_parson']}'); if (mounted) Navigator.pop(context); }
      else { widget.onError(resp['message'] ?? 'Failed'); }
    } catch (e) { setState(() => _assigning = false); widget.onError('Failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(width: 520, constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
            child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22)), const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), Text('Entry: ${widget.entry.projectName}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis)])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white))])),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _tsNavy)), const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))), child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5))),
            const SizedBox(height: 20), const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _tsNavy)), const SizedBox(height: 8),
            Row(children: ['Low', 'Medium', 'High'].map((pr) { final isSel = _priority == pr; final color = pr == 'High' ? _tsRed : pr == 'Medium' ? _tsOrange : _tsGreen;
              return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: InkWell(onTap: () => setState(() => _priority = pr), borderRadius: BorderRadius.circular(10), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: isSel ? color : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isSel ? color : Colors.grey[300]!), boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : []), child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700])))))));}).toList()),
            const SizedBox(height: 20), const Text('Assign To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _tsNavy)), const SizedBox(height: 8),
            TextField(controller: _searchCtrl, decoration: InputDecoration(hintText: 'Search employees…', prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]), filled: true, fillColor: const Color(0xFFF7F9FC), contentPadding: const EdgeInsets.symmetric(vertical: 0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _tsNavy, width: 1.5)))),
            const SizedBox(height: 8),
            _loading ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _tsNavy)))
                : _filtered.isEmpty ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                : Container(constraints: const BoxConstraints(maxHeight: 240), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                    child: ListView.separated(shrinkWrap: true, itemCount: _filtered.length, separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                      itemBuilder: (_, i) {
                        final emp = _filtered[i]; final isSel = _selectedEmp?['_id'] == emp['_id'];
                        return InkWell(onTap: () => setState(() => _selectedEmp = isSel ? null : emp), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), color: isSel ? _tsNavy.withOpacity(0.06) : Colors.transparent,
                            child: Row(children: [CircleAvatar(radius: 18, backgroundColor: isSel ? _tsNavy : _tsNavy.withOpacity(0.10), child: Text((emp['name_parson'] ?? 'U')[0].toUpperCase(), style: TextStyle(color: isSel ? Colors.white : _tsNavy, fontWeight: FontWeight.bold, fontSize: 13))), const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), if (emp['email'] != null) Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                if (emp['role'] != null) Container(margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _tsNavy.withOpacity(0.08), borderRadius: BorderRadius.circular(4)), child: Text(emp['role'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _tsNavy)))])),
                              if (isSel) const Icon(Icons.check_circle, color: _tsNavy, size: 20)]))); })),
          ]))),
          Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFF7F9FC), border: Border(top: BorderSide(color: Color(0xFFEEF2F7))), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: (_selectedEmp == null || _assigning) ? null : _assign, style: ElevatedButton.styleFrom(backgroundColor: _tsNavy, foregroundColor: Colors.white, disabledBackgroundColor: _tsNavy.withOpacity(0.4), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _assigning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(_selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))),
            ])),
        ])));
  }
}

// =============================================================================
// BULK IMPORT TIMESHEETS DIALOG
// =============================================================================

class _BulkImportTimesheetsDialog extends StatefulWidget {
  final List<Project> projects;
  final Future<void> Function() onImportComplete;
  const _BulkImportTimesheetsDialog({required this.projects, required this.onImportComplete});
  @override
  State<_BulkImportTimesheetsDialog> createState() => _BulkImportTimesheetsDState();
}

class _BulkImportTimesheetsDState extends State<_BulkImportTimesheetsDialog> {
  bool _downloading = false, _uploading = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = <List<dynamic>>[
        ['Project Name*', 'Task Name', 'Staff Name', 'Date* (YYYY-MM-DD)', 'Hours*', 'Billable (Yes/No)', 'Notes'],
        ...(widget.projects.isNotEmpty ? widget.projects.take(2).map((p) => [p.projectName, 'Development', 'John Doe', '2025-01-15', '8', 'Yes', 'Sample work']) : [['My Project', 'Task 1', 'Staff Name', '2025-01-01', '8', 'Yes', 'Notes here']]),
        ['--- INSTRUCTIONS ---', 'Task Name = optional', 'Staff Name = optional', 'Date format: YYYY-MM-DD', 'Hours > 0', 'Billable = Yes or No', 'DELETE THIS ROW'],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'timesheets_import_template');
      setState(() => _downloading = false);
      _showSnack('Template downloaded!', _tsGreen);
    } catch (e) { setState(() => _downloading = false); _showSnack('Download failed: $e', _tsRed); }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first; final bytes = file.bytes;
      if (bytes == null) { _showSnack('Could not read file', _tsRed); return; }
      setState(() { _fileName = file.name; _uploading = true; _results = null; });
      final ext  = file.extension?.toLowerCase() ?? '';
      final rows = ext == 'csv' ? _parseCSV(bytes) : _parseExcel(bytes);
      if (rows.length < 2) throw Exception('File needs header + at least one data row');
      final projectMap = { for (final p in widget.projects) p.projectName.toLowerCase(): p.id };
      final List<Map<String, dynamic>> valid = [];
      final List<String> errors = [];
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty || _sv(row, 0).startsWith('---')) continue;
        try {
          final projectName = _sv(row, 0);
          final hours       = double.tryParse(_sv(row, 4)) ?? 0;
          final date        = _sv(row, 3);
          if (projectName.isEmpty) throw Exception('Project Name required');
          if (hours <= 0)          throw Exception('Hours must be > 0');
          if (date.isEmpty)        throw Exception('Date required');
          DateTime.parse(date);
          final projectId = projectMap[projectName.toLowerCase()] ?? '';
          final billableStr = _sv(row, 5).toLowerCase();
          valid.add({
            'projectId': projectId, 'projectName': projectName,
            'taskName':  _sv(row, 1), 'userName': _sv(row, 2),
            'date': date, 'hours': hours,
            'isBillable': billableStr != 'no' && billableStr != 'false',
            'notes': _sv(row, 6),
          });
        } catch (e) { errors.add('Row ${i+1}: $e'); }
      }
      if (valid.isEmpty) throw Exception('No valid data found.');
      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${valid.length} time entr${valid.length == 1 ? 'y' : 'ies'} will be imported.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          if (errors.isNotEmpty) ...[const SizedBox(height: 12), Text('${errors.length} row(s) skipped', style: const TextStyle(color: _tsRed, fontWeight: FontWeight.w600))],
          const SizedBox(height: 12), const Text('Do you want to proceed?'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _tsNavy, foregroundColor: Colors.white), child: const Text('Import'))],
      ));
      if (confirmed != true) { setState(() { _uploading = false; _fileName = null; }); return; }
      final importResult = await TimesheetService.bulkImport(valid);
      setState(() {
        _uploading = false;
        _results = { 'success': importResult['data']['successCount'], 'failed': importResult['data']['failedCount'], 'total': importResult['data']['totalProcessed'] };
      });
      if ((_results!['success'] ?? 0) > 0) { _showSnack('✅ ${_results!['success']} entr${_results!['success'] == 1 ? 'y' : 'ies'} imported!', _tsGreen); await widget.onImportComplete(); }
      if ((_results!['failed'] ?? 0) > 0)  _showSnack('⚠ ${_results!['failed']} failed', _tsOrange);
    } catch (e) { setState(() { _uploading = false; _fileName = null; }); _showSnack('Import failed: $e', _tsRed); }
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex = excel_pkg.Excel.decodeBytes(bytes);
    final sheet = ex.tables.keys.first;
    return (ex.tables[sheet]?.rows ?? []).map((row) => row.map((cell) {
      if (cell?.value == null) return '';
      if (cell!.value is excel_pkg.TextCellValue) return (cell.value as excel_pkg.TextCellValue).value;
      return cell.value;
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true).split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).map((line) {
      final fields = <String>[]; final buf = StringBuffer(); bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') { if (inQuotes && i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; } else inQuotes = !inQuotes; }
        else if (ch == ',' && !inQuotes) { fields.add(buf.toString().trim()); buf.clear(); }
        else buf.write(ch);
      }
      fields.add(buf.toString().trim());
      return fields.map((f) => f.startsWith('"') && f.endsWith('"') ? f.substring(1, f.length - 1) : f).toList();
    }).toList();
  }

  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(width: MediaQuery.of(context).size.width > 600
          ? 560
          : MediaQuery.of(context).size.width * 0.92, padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _tsNavy.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.upload_file_rounded, color: _tsNavy, size: 24)), const SizedBox(width: 14),
          const Text('Import Timesheets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const Spacer(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
        const SizedBox(height: 24),
        _importStep(step: '1', color: _tsBlue, icon: Icons.download_rounded, title: 'Download Template', subtitle: 'Get the Excel template with project names pre-filled.', buttonLabel: _downloading ? 'Downloading…' : 'Download Template', onPressed: _downloading || _uploading ? null : _downloadTemplate),
        const SizedBox(height: 16),
        _importStep(step: '2', color: _tsGreen, icon: Icons.upload_rounded, title: 'Upload Filled File', subtitle: 'Fill in the template and upload (XLSX / CSV).', buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'), onPressed: _downloading || _uploading ? null : _uploadFile),
        if (_fileName != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
            child: Row(children: [Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)))]))],
        if (_results != null) ...[const Divider(height: 28),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 10),
            _resultRow('Total', '${_results!['total']}', Colors.blue), const SizedBox(height: 6),
            _resultRow('Imported', '${_results!['success']}', _tsGreen), const SizedBox(height: 6),
            _resultRow('Failed', '${_results!['failed']}', _tsRed),
          ])),
          const SizedBox(height: 16), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: _tsNavy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Close')))],
      ])));
  }

  Widget _importStep({required String step, required Color color, required IconData icon, required String title, required String subtitle, required String buttonLabel, required VoidCallback? onPressed}) {
    final circle = Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]))]);
    final button = ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 16), label: Text(buttonLabel, style: const TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, disabledBackgroundColor: color.withOpacity(0.5), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 12), button]);
      }));
  }

  Widget _resultRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w500)), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)))]);
  }
}