// ============================================================================
// VENDORS LIST PAGE
// - Recurring Invoices / Quotes UI pattern (3-breakpoint top bar, gradient
//   stat cards, dark navy table, ellipsis pagination)
// - Import button  → BulkImportVendorsDialog (2-step: template + upload)
// - Export button  → Excel / PDF export
// - Raise Ticket   → row PopupMenu → overlay with employee search + assign
// - Share button   → share_plus (web + mobile)
// - WhatsApp       → url_launcher wa.me (vendor phoneNumber, web + mobile)
// ============================================================================
// File: lib/screens/billing/pages/vendors_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../core/services/tms_service.dart';
import 'new_vendor.dart';
import 'vendor_detail_page.dart';

// ─── colour palette ──────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);

class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label, required this.value,
    required this.icon,  required this.color,
    required this.gradientColors,
  });
}

// ============================================================================
//  DATA MODEL
// ============================================================================

class VendorData {
  final String id;
  final String name;
  final String companyName;
  final String email;
  final String phoneNumber;
  final String status;
  final String type;
  final DateTime createdDate;

  VendorData({
    required this.id,
    required this.name,
    required this.companyName,
    required this.email,
    required this.phoneNumber,
    required this.status,
    required this.type,
    required this.createdDate,
  });

  factory VendorData.fromJson(Map<String, dynamic> json) {
    return VendorData(
      id: json['_id'] ?? json['vendorId'] ?? '',
      name: json['vendorName'] ?? '',
      companyName: json['companyName'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      status: json['status'] ?? 'Active',
      type: json['vendorType'] ?? 'External Vendor',
      createdDate: json['createdDate'] != null
          ? DateTime.parse(json['createdDate'])
          : DateTime.now(),
    );
  }
}

// =============================================================================
//  MAIN PAGE
// =============================================================================

class VendorsListPage extends StatefulWidget {
  const VendorsListPage({Key? key}) : super(key: key);
  @override
  State<VendorsListPage> createState() => _VendorsListPageState();
}

class _VendorsListPageState extends State<VendorsListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<VendorData> _vendors  = [];
  List<VendorData> _filtered = [];
  Map<String, dynamic>? _statistics;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String _quickFilter  = 'All Vendors';
  String _typeFilter   = 'All Types';
  String _statusFilter = 'All Statuses';
  bool   _showAdvanced = false;

  final List<String> _quickFilters  = ['All Vendors', 'Active', 'Inactive', 'Blocked'];
  final List<String> _typeFilters   = ['All Types', 'Internal Employee', 'External Vendor', 'Contractor', 'Freelancer'];
  final List<String> _statusFilters = ['All Statuses', 'Active', 'Inactive', 'Blocked', 'Pending Approval'];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage = 1;
  int _totalPages  = 1;
  final int _perPage = 20;

  // ── selection ─────────────────────────────────────────────────────────────
  Set<int> _selectedRows = {};
  bool _selectAll = false;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadVendors();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadVendors() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await BillingVendorsService.getAllVendors(limit: 1000);
      if (result['success'] == true) {
        final data      = result['data'];
        final list      = (data['vendors'] as List)
            .map((j) => VendorData.fromJson(j)).toList();
        setState(() {
          _vendors    = list;
          _statistics = data['statistics'];
          _isLoading  = false;
        });
        _applyFilters();
      } else {
        throw Exception(result['message'] ?? 'Failed to load vendors');
      }
    } on BillingVendorsException catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toUserMessage(); });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _refresh() async {
    await _loadVendors();
    _showSuccess('List refreshed');
  }

  // ── filtering ─────────────────────────────────────────────────────────────

  void _applyFilters() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _vendors.where((v) {
        if (q.isNotEmpty &&
            !v.name.toLowerCase().contains(q) &&
            !v.companyName.toLowerCase().contains(q) &&
            !v.email.toLowerCase().contains(q) &&
            !v.phoneNumber.contains(q)) return false;
        if (_quickFilter  != 'All Vendors'  && v.status != _quickFilter)  return false;
        if (_typeFilter   != 'All Types'    && v.type   != _typeFilter)   return false;
        if (_statusFilter != 'All Statuses' && v.status != _statusFilter) return false;
        return true;
      }).toList();
      _totalPages  = (_filtered.length / _perPage).ceil().clamp(1, 9999);
      if (_currentPage > _totalPages) _currentPage = _totalPages;
      _selectedRows.clear();
      _selectAll = false;
    });
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _quickFilter  = 'All Vendors';
      _typeFilter   = 'All Types';
      _statusFilter = 'All Statuses';
      _showAdvanced = false;
      _currentPage  = 1;
    });
    _applyFilters();
  }

  bool get _hasFilter => _quickFilter != 'All Vendors' || _typeFilter != 'All Types' ||
      _statusFilter != 'All Statuses' || _searchCtrl.text.isNotEmpty;

  List<VendorData> get _pageItems {
    final s = (_currentPage - 1) * _perPage;
    final e = (s + _perPage).clamp(0, _filtered.length);
    return _filtered.sublist(s, e);
  }

  // ── selection ─────────────────────────────────────────────────────────────

  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      _selectedRows = _selectAll
          ? Set.from(List.generate(_pageItems.length, (i) => i))
          : {};
    });
  }

  void _toggleRow(int i) {
    setState(() {
      _selectedRows.contains(i) ? _selectedRows.remove(i) : _selectedRows.add(i);
      _selectAll = _selectedRows.length == _pageItems.length;
    });
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewVendorPage()));
    if (ok == true) _loadVendors();
  }

  void _openEdit(VendorData v) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewVendorPage(vendorId: v.id)));
    if (ok == true) _loadVendors();
  }

  // ── vendor actions ────────────────────────────────────────────────────────

  void _viewDetails(VendorData v) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorDetailPage(vendorId: v.id)),
    ).then((result) { if (result == true) _loadVendors(); });
  }

  Future<void> _deleteVendor(VendorData v) async {
    final ok = await _confirmDialog(
      title: 'Delete Vendor',
      message: 'Delete "${v.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      setState(() => _isLoading = true);
      final result = await BillingVendorsService.deleteVendor(v.id);
      if (result['success'] == true) {
        _showSuccess('Vendor deleted');
        _loadVendors();
      } else {
        throw Exception(result['message']);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to delete: $e');
    }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _shareVendor(VendorData v) async {
    final text = 'Vendor Details\n'
        '─────────────────────────\n'
        'Name    : ${v.name}\n'
        'Company : ${v.companyName.isNotEmpty ? v.companyName : '-'}\n'
        'Email   : ${v.email}\n'
        'Phone   : ${v.phoneNumber}\n'
        'Type    : ${v.type}\n'
        'Status  : ${v.status}';
    try {
      await Share.share(text, subject: 'Vendor: ${v.name}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(VendorData v) async {
    final phone = v.phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (phone.isEmpty) {
      _showError('Phone number not available for this vendor.');
      return;
    }
    final msg = Uri.encodeComponent(
      'Hello ${v.name},\n\n'
      'This is a message from Abra Travels Management.\n\n'
      '${v.companyName.isNotEmpty ? 'Company: ${v.companyName}\n' : ''}'
      'Vendor Type: ${v.type}\n\n'
      'Please feel free to contact us for any queries.\nThank you!',
    );
    final url = Uri.parse('https://wa.me/$phone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket(VendorData v) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        vendor: v,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError: (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  void _handleExport() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export Vendors', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.table_chart, color: _green),
            title: const Text('Excel (XLSX)'),
            onTap: () { Navigator.pop(context); _exportExcel(); },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: _red),
            title: const Text('PDF'),
            onTap: () { Navigator.pop(context); _exportPDF(); },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _exportExcel() async {
    try {
      if (_filtered.isEmpty) { _showError('No vendors to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Name', 'Company Name', 'Type', 'Status', 'Email', 'Phone', 'Created Date'],
        ..._filtered.map((v) => [
          v.name, v.companyName, v.type, v.status, v.email, v.phoneNumber,
          DateFormat('dd/MM/yyyy').format(v.createdDate),
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'vendors');
      _showSuccess('✅ Excel downloaded (${_filtered.length} vendors)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  Future<void> _exportPDF() async {
    try {
      if (_filtered.isEmpty) { _showError('No vendors to export'); return; }
      _showSuccess('Preparing PDF…');
      await ExportHelper.exportToPDF(
        title: 'Vendors Report',
        headers: ['Name', 'Company', 'Email', 'Phone', 'Status'],
        data: _filtered.map((v) => [v.name, v.companyName, v.email, v.phoneNumber, v.status]).toList(),
        filename: 'vendors',
      );
      _showSuccess('✅ PDF downloaded');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportVendorsDialog(onImportComplete: _loadVendors),
    );
  }

  // ── snackbars ─────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _confirmDialog({
    required String title, required String message,
    required String confirmLabel, Color confirmColor = _navy,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text('Vendors'),
        backgroundColor: const Color(0xFF1e3a8a),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          if (_showAdvanced) _buildAdvancedFilters(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _filtered.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _filtered.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _quickFilterDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 240),
    const SizedBox(width: 10),
    _iconBtn(Icons.filter_list, () => setState(() => _showAdvanced = !_showAdvanced),
        tooltip: 'Advanced Filters', color: _showAdvanced ? _navy : const Color(0xFF7F8C8D),
        bg: _showAdvanced ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const Spacer(),
    _actionBtn('New Vendor', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _filtered.isEmpty ? null : _handleExport),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _quickFilterDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 190),
      const SizedBox(width: 8),
      _iconBtn(Icons.filter_list, () => setState(() => _showAdvanced = !_showAdvanced),
          tooltip: 'Filters', color: _showAdvanced ? _navy : const Color(0xFF7F8C8D),
          bg: _showAdvanced ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Vendor', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _filtered.isEmpty ? null : _handleExport),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _quickFilterDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _iconBtn(Icons.filter_list, () => setState(() => _showAdvanced = !_showAdvanced),
          color: _showAdvanced ? _navy : const Color(0xFF7F8C8D),
          bg: _showAdvanced ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _filtered.isEmpty ? null : _handleExport),
    ])),
  ]);

  // ── advanced filters ──────────────────────────────────────────────────────

  Widget _buildAdvancedFilters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: LayoutBuilder(builder: (_, c) {
        final typeDD = _advDropdown(_typeFilter, _typeFilters,
            (v) { setState(() { _typeFilter = v!; _currentPage = 1; }); _applyFilters(); });
        final statusDD = _advDropdown(_statusFilter, _statusFilters,
            (v) { setState(() { _statusFilter = v!; _currentPage = 1; }); _applyFilters(); });
        final clearBtn = TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.clear, size: 16),
          label: const Text('Clear All'),
          style: TextButton.styleFrom(foregroundColor: _red),
        );
        if (c.maxWidth < 700) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Filters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
            const SizedBox(height: 8),
            typeDD,
            const SizedBox(height: 8),
            statusDD,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: clearBtn),
          ]);
        }
        return Row(children: [
          const Text('Filters:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(width: 12),
          SizedBox(width: 200, child: typeDD),
          const SizedBox(width: 12),
          SizedBox(width: 200, child: statusDD),
          const Spacer(),
          if (_hasFilter) clearBtn,
        ]);
      }),
    );
  }

  Widget _advDropdown(String value, List<String> items, ValueChanged<String?> onChange) {
    return Container(
      height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50)),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChange,
        ),
      ),
    );
  }

  // ── reusable widgets ──────────────────────────────────────────────────────

  Widget _quickFilterDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _quickFilter,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _quickFilters.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _quickFilter = v; _currentPage = 1; }); _applyFilters(); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search name, email, phone, company…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchCtrl.clear(); setState(() => _currentPage = 1); _applyFilters(); })
            : null,
        filled: true, fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  // ── stats cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final total    = _vendors.length;
    final active   = _vendors.where((v) => v.status == 'Active').length;
    final inactive = _vendors.where((v) => v.status == 'Inactive').length;
    final blocked  = _vendors.where((v) => v.status == 'Blocked').length;
    final external = _vendors.where((v) => v.type == 'External Vendor').length;

    final cards = [
      _StatCardData(label: 'Total Vendors',    value: total.toString(),    icon: Icons.people_outline,         color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Active',           value: active.toString(),   icon: Icons.check_circle_outline,   color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Inactive',         value: inactive.toString(), icon: Icons.pause_circle_outline,   color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Blocked',          value: blocked.toString(),  icon: Icons.block_outlined,         color: _red,    gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'External Vendors', value: external.toString(), icon: Icons.business_outlined,      color: _purple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl, scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(
              width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _buildStatCard(e.value, compact: true),
            )).toList()),
          );
        }
        return Row(children: cards.asMap().entries.map((e) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
            child: _buildStatCard(e.value, compact: false),
          ),
        )).toList());
      }),
    );
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                child: Icon(d.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(d.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: d.color)),
              ])),
            ]),
    );
  }

  // ── table ─────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    final items = _pageItems;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl, scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                  headingRowHeight: 52, dataRowMinHeight: 60, dataRowMaxHeight: 76,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 18, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E), onChanged: _toggleSelectAll))),
                    const DataColumn(label: SizedBox(width: 170, child: Text('NAME'))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('COMPANY NAME'))),
                    const DataColumn(label: SizedBox(width: 180, child: Text('EMAIL'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('PHONE'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('TYPE'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 150, child: Text('ACTIONS'))),
                  ],
                  rows: items.asMap().entries.map((e) => _buildRow(e.key, e.value)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(int index, VendorData v) {
    final isSel = _selectedRows.contains(index);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleRow(index))),

        // Name
        DataCell(SizedBox(width: 170, child: InkWell(
          onTap: () => _openEdit(v),
          child: Text(v.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
        ))),

        // Company
        DataCell(SizedBox(width: 160, child: Text(v.companyName.isNotEmpty ? v.companyName : '-',
            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey[700])))),

        // Email
        DataCell(SizedBox(width: 180, child: Text(v.email,
            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey[700])))),

        // Phone
        DataCell(SizedBox(width: 120, child: Text(v.phoneNumber, style: const TextStyle(fontSize: 13)))),

        // Type
        DataCell(SizedBox(width: 130, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: _navy.withOpacity(0.06), borderRadius: BorderRadius.circular(6)),
          child: Text(v.type, style: const TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ))),

        // Status
        DataCell(SizedBox(width: 110, child: _statusBadge(v.status))),

        // Actions
        DataCell(SizedBox(width: 150, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _shareVendor(v),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(v),
          //   child: Container(width: 32, height: 32,
          //       decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
          //       child: const Icon(Icons.chat, size: 16, color: Color(0xFF25D366))),
          // )),
          // const SizedBox(width: 4),
          // More
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('view',   Icons.visibility_outlined,          _blue,   'View Details'),
              _menuItem('edit',   Icons.edit_outlined,                _navy,   'Edit'),
              _menuItem('ticket', Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
              _menuItem('delete', Icons.delete_outline,               _red,    'Delete', textColor: _red),
            ],
            onSelected: (val) {
              switch (val) {
                case 'view':   _viewDetails(v); break;
                case 'edit':   _openEdit(v);    break;
                case 'ticket': _raiseTicket(v); break;
                case 'delete': _deleteVendor(v); break;
              }
            },
          ),
        ]))),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color iconColor, String label, {Color? textColor}) {
    return PopupMenuItem(value: value, child: ListTile(
      leading: Icon(icon, size: 17, color: iconColor),
      title: Text(label, style: TextStyle(color: textColor)),
      contentPadding: EdgeInsets.zero, dense: true,
    ));
  }

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'Active':           [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'Inactive':         [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'Blocked':          [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'Pending Approval': [Color(0xFFFEF3C7), Color(0xFFB45309)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11), overflow: TextOverflow.ellipsis),
      ]),
    );
  }

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
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: LayoutBuilder(builder: (_, c) {
        return Wrap(
          alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
          children: [
            Text(
              'Showing ${(_currentPage - 1) * _perPage + 1}–${(_currentPage * _perPage).clamp(0, _filtered.length)} of ${_filtered.length}'
              '${_filtered.length != _vendors.length ? ' (filtered from ${_vendors.length})' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () => setState(() { _currentPage--; _applyFilters(); })),
              const SizedBox(width: 4),
              if (pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))),
              ],
              ...pages.map((p) => _pageNumBtn(p)),
              if (pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () => setState(() { _currentPage++; _applyFilters(); })),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _applyFilters(); } },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2), width: 34, height: 34,
        decoration: BoxDecoration(color: isActive ? _navy : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? _navy : Colors.grey[300]!)),
        child: Center(child: Text('$page', style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.white : Colors.grey[700]))),
      ),
    );
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: enabled ? Colors.white : Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
        child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ── empty / error states ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.people_outline, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Vendors Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasFilter ? 'Try adjusting your filters' : 'Add your first vendor to get started',
          style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasFilter ? _clearFilters : _openNew,
        icon: Icon(_hasFilter ? Icons.filter_list_off : Icons.add),
        label: Text(_hasFilter ? 'Clear Filters' : 'Add Vendor', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Vendors', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _loadVendors, icon: const Icon(Icons.refresh),
        label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final VendorData vendor;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({required this.vendor, required this.onTicketRaised, required this.onError});

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered  = [];
  Map<String, dynamic>?       _selectedEmp;
  bool _loading   = true;
  bool _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(resp['data']);
        _filtered  = _employees;
        _loading   = false;
      });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty ? _employees : _employees.where((e) =>
        (e['name_parson'] ?? '').toLowerCase().contains(q) ||
        (e['email'] ?? '').toLowerCase().contains(q) ||
        (e['role'] ?? '').toLowerCase().contains(q)).toList();
    });
  }

  String _buildMessage() {
    final v = widget.vendor;
    return 'Vendor "${v.name}" requires attention.\n\n'
           'Vendor Details:\n'
           '• Company: ${v.companyName.isNotEmpty ? v.companyName : 'N/A'}\n'
           '• Type: ${v.type}\n'
           '• Status: ${v.status}\n'
           '• Email: ${v.email}\n'
           '• Phone: ${v.phoneNumber}\n\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: 'Vendor: ${widget.vendor.name}',
        message:  _buildMessage(),
        priority: _priority,
        timeline: 1440,
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised('Ticket assigned to ${_selectedEmp!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else {
        widget.onError(resp['message'] ?? 'Failed to create ticket');
      }
    } catch (e) {
      setState(() => _assigning = false);
      widget.onError('Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Vendor: ${widget.vendor.name}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Body
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5)),
              ),
              const SizedBox(height: 20),

              // Priority
              const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Row(children: ['Low', 'Medium', 'High'].map((pr) {
                final isSel = _priority == pr;
                final color = pr == 'High' ? _red : pr == 'Medium' ? _orange : _green;
                return Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _priority = pr),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSel ? color : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSel ? color : Colors.grey[300]!),
                        boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
                      ),
                      child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700]))),
                    ),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 20),

              // Employee search
              const Text('Assign To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
                  filled: true, fillColor: const Color(0xFFF7F9FC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
              _loading
                  ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _navy)))
                  : _filtered.isEmpty
                      ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                            itemBuilder: (_, i) {
                              final emp   = _filtered[i];
                              final isSel = _selectedEmp?['_id'] == emp['_id'];
                              return InkWell(
                                onTap: () => setState(() => _selectedEmp = isSel ? null : emp),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
                                      child: Text(
                                        (emp['name_parson'] ?? 'U')[0].toUpperCase(),
                                        style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (emp['email'] != null)
                                        Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                      if (emp['role'] != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                                          child: Text(emp['role'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy)),
                                        ),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
            ]),
          )),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FC),
              border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white,
                  disabledBackgroundColor: _navy.withOpacity(0.4),
                  elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _assigning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee',
                        style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis,
                      ),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  BULK IMPORT VENDORS DIALOG (2-step pattern)
// =============================================================================

class BulkImportVendorsDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportVendorsDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportVendorsDialog> createState() => _BulkImportVendorsDialogState();
}

class _BulkImportVendorsDialogState extends State<BulkImportVendorsDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = <List<dynamic>>[
        [
          'Vendor Type*',
          'Vendor Name*',
          'Company Name',
          'Email*',
          'Phone Number*',
          'Alternate Phone',
          'Status',
          'Bank Details Provided (Yes/No)',
          'Account Holder Name',
          'Bank Name',
          'Account Number',
          'IFSC Code',
          'Address Provided (Yes/No)',
          'Address Line 1',
          'Address Line 2',
          'City',
          'State',
          'Postal Code',
          'Country',
          'GST Number',
          'PAN Number',
          'Service Category',
          'Notes',
        ],
        // Example row 1
        ['External Vendor', 'John Doe', 'ABC Transport', 'john@abctransport.com', '9876543210', '9876543211', 'Active', 'Yes', 'John Doe', 'HDFC Bank', '12345678901234', 'HDFC0001234', 'Yes', '123 Main St', 'Apt 4B', 'Bangalore', 'Karnataka', '560001', 'India', '29ABCDE1234F1Z5', 'ABCDE1234F', 'Logistics', 'Preferred vendor'],
        // Example row 2
        ['Internal Employee', 'Jane Smith', '', 'jane@company.com', '9123456789', '', 'Active', 'No', '', '', '', '', 'No', '', '', '', '', '', '', '', '', 'HR', 'Internal staff'],
        // Instructions
        ['INSTRUCTIONS:', '* = required', 'Type: Internal Employee/External Vendor/Contractor/Freelancer', 'Status: Active/Inactive/Blocked/Pending Approval', 'Phone: 10 digits', 'Delete this row before uploading'],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'vendors_import_template');
      setState(() => _downloading = false);
      _showSnack('Template downloaded!', _green);
    } catch (e) {
      setState(() => _downloading = false);
      _showSnack('Download failed: $e', _red);
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false, withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file  = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) { _showSnack('Could not read file', _red); return; }

      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      final ext = file.extension?.toLowerCase() ?? '';
      final rows = (ext == 'csv') ? _parseCSV(bytes) : _parseExcel(bytes);

      if (rows.length < 2) throw Exception('File needs header + at least one data row');

      final List<Map<String, dynamic>> valid  = [];
      final List<String>               errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty) continue;
        if (_sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors = <String>[];
        final vendorType   = _sv(row, 0);
        final vendorName   = _sv(row, 1);
        final companyName  = _sv(row, 2);
        final email        = _sv(row, 3);
        final phone        = _parsePhone(_sv(row, 4));
        final altPhone     = _parsePhone(_sv(row, 5));
        final status       = _sv(row, 6, 'Active');
        final bankProvided = _sv(row, 7).toLowerCase() == 'yes';
        final accHolder    = _sv(row, 8);
        final bankName     = _sv(row, 9);
        final accNumber    = _parsePhone(_sv(row, 10));
        final ifscCode     = _sv(row, 11);
        final addrProvided = _sv(row, 12).toLowerCase() == 'yes';
        final addr1        = _sv(row, 13);
        final addr2        = _sv(row, 14);
        final city         = _sv(row, 15);
        final state        = _sv(row, 16);
        final postal       = _sv(row, 17);
        final country      = _sv(row, 18, 'India');
        final gst          = _sv(row, 19);
        final pan          = _sv(row, 20);
        final category     = _sv(row, 21);
        final notes        = _sv(row, 22);

        if (vendorType.isEmpty) rowErrors.add('Vendor Type required');
        if (vendorName.isEmpty) rowErrors.add('Vendor Name required');
        if (email.isEmpty)      rowErrors.add('Email required');
        else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) rowErrors.add('Invalid email');
        if (phone.isEmpty)      rowErrors.add('Phone required');
        else if (phone.length < 10) rowErrors.add('Phone must be 10 digits');

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        valid.add({
          'vendorType': vendorType, 'vendorName': vendorName, 'companyName': companyName,
          'email': email, 'phoneNumber': phone, 'alternatePhone': altPhone, 'status': status,
          'bankDetailsProvided': bankProvided, 'accountHolderName': accHolder, 'bankName': bankName,
          'accountNumber': accNumber, 'ifscCode': ifscCode,
          'addressProvided': addrProvided, 'addressLine1': addr1, 'addressLine2': addr2,
          'city': city, 'state': state, 'postalCode': postal, 'country': country,
          'gstNumber': gst, 'panNumber': pan, 'serviceCategory': category, 'notes': notes,
        });
      }

      if (valid.isEmpty) throw Exception('No valid vendor data found');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valid.length} vendor(s) will be imported.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${errors.length} row(s) skipped:', style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)),
                child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12, color: _red))),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Do you want to proceed?'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirmed != true) { setState(() { _uploading = false; _fileName = null; }); return; }

      final importResult = await BillingVendorsService.bulkImportVendors(valid);

      setState(() {
        _uploading = false;
        _results = {
          'success': importResult['data']['successCount'],
          'failed':  importResult['data']['failedCount'],
          'total':   importResult['data']['totalProcessed'],
          'errors':  importResult['data']['errors'] ?? [],
        };
      });

      if (importResult['success'] == true) {
        _showSnack('✅ ${_results!['success']} vendor(s) imported!', _green);
        await widget.onImportComplete();
      }
      if ((_results!['failed'] ?? 0) > 0) {
        _showSnack('⚠ ${_results!['failed']} failed', _orange);
      }

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex    = excel_pkg.Excel.decodeBytes(bytes);
    final sheet = ex.tables.keys.first;
    return (ex.tables[sheet]?.rows ?? []).map((row) => row.map((cell) {
      if (cell?.value == null) return '';
      if (cell!.value is excel_pkg.TextCellValue) return (cell.value as excel_pkg.TextCellValue).value;
      return cell.value;
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true)
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map(_parseCSVLine)
        .toList();
  }

  List<String> _parseCSVLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; }
        else { inQuotes = !inQuotes; }
      } else if (ch == ',' && !inQuotes) {
        fields.add(buf.toString().trim()); buf.clear();
      } else { buf.write(ch); }
    }
    fields.add(buf.toString().trim());
    return fields;
  }

  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
  }

  String _parsePhone(String s) {
    if (s.isEmpty) return '';
    if (s.toUpperCase().contains('E')) {
      try { return double.parse(s).round().toString(); } catch (_) {}
    }
    if (s.contains('.')) {
      try { return double.parse(s).round().toString(); } catch (_) {}
    }
    return s.replaceAll(RegExp(r'[^\d]'), '');
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width > 600
            ? 560
            : MediaQuery.of(context).size.width * 0.92,
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24),
            ),
            const SizedBox(width: 14),
            const Text('Import Vendors', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),

          // Step 1
          _importStep(
            step: '1', color: _blue, icon: Icons.download_rounded,
            title: 'Download Template',
            subtitle: 'Get the Excel template with all 23 required columns and example rows.',
            buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
            onPressed: _downloading || _uploading ? null : _downloadTemplate,
          ),
          const SizedBox(height: 16),

          // Step 2
          _importStep(
            step: '2', color: _green, icon: Icons.upload_rounded,
            title: 'Upload Filled File',
            subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).',
            buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'),
            onPressed: _downloading || _uploading ? null : _uploadFile,
          ),

          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600))),
              ]),
            ),
          ],

          if (_results != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                _resultRow('Total Processed',       '${_results!['total']}',   Colors.blue),
                const SizedBox(height: 6),
                _resultRow('Successfully Imported', '${_results!['success']}', _green),
                const SizedBox(height: 6),
                _resultRow('Failed',                '${_results!['failed']}',  _red),
                if ((_results!['errors'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: _red)),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(child: Text((_results!['errors'] as List).join('\n'), style: const TextStyle(fontSize: 12, color: _red))),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Close'),
            )),
          ],
        ]),
      ),
    );
  }

  Widget _importStep({
    required String step, required Color color, required IconData icon,
    required String title, required String subtitle,
    required String buttonLabel, required VoidCallback? onPressed,
  }) {
    final circle = Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        disabledBackgroundColor: color.withOpacity(0.5), elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 12), button]);
      }),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

class VendorDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> vendorData;
  const VendorDetailsDialog({Key? key, required this.vendorData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person, color: _blue, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(vendorData['vendorName'] ?? 'Unknown',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text(vendorData['vendorId'] ?? '', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ])),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 32),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section('Basic Information', [
              _infoRow('Vendor Type',     vendorData['vendorType']),
              _infoRow('Name',            vendorData['vendorName']),
              _infoRow('Company Name',    vendorData['companyName']),
              _infoRow('Email',           vendorData['email']),
              _infoRow('Phone Number',    vendorData['phoneNumber']),
              _infoRow('Alternate Phone', vendorData['alternatePhone']),
              _infoRow('Status',          vendorData['status']),
            ]),
            if (vendorData['bankDetailsProvided'] == true) ...[
              const SizedBox(height: 24),
              _section('Bank Details', [
                _infoRow('Account Holder', vendorData['accountHolderName']),
                _infoRow('Bank Name',      vendorData['bankName']),
                _infoRow('Account Number', vendorData['accountNumber']),
                _infoRow('IFSC Code',      vendorData['ifscCode']),
              ]),
            ],
            if (vendorData['addressProvided'] == true) ...[
              const SizedBox(height: 24),
              _section('Address', [
                _infoRow('Address Line 1', vendorData['addressLine1']),
                _infoRow('Address Line 2', vendorData['addressLine2']),
                _infoRow('City',           vendorData['city']),
                _infoRow('State',          vendorData['state']),
                _infoRow('Postal Code',    vendorData['postalCode']),
                _infoRow('Country',        vendorData['country']),
              ]),
            ],
            const SizedBox(height: 24),
            _section('Additional Information', [
              _infoRow('GST Number',       vendorData['gstNumber']),
              _infoRow('PAN Number',       vendorData['panNumber']),
              _infoRow('Service Category', vendorData['serviceCategory']),
              _infoRow('Notes',            vendorData['notes']),
            ]),
          ]))),
          const Divider(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ]),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _infoRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 180, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2C3E50), fontSize: 14))),
        Expanded(child: Text(value.toString(), style: TextStyle(color: Colors.grey[800], fontSize: 14))),
      ]),
    );
  }
}