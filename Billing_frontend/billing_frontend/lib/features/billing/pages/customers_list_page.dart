// ============================================================================
// CUSTOMERS LIST PAGE - Credit Notes UI Pattern + Full Original Functionality
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/utils/export_helper.dart';
import '../../../../app/config/api_config.dart';
import '../app_top_bar.dart';
import 'new_customer.dart';
import 'customer_detail_page.dart';
import '../../../../core/services/billing_customers_service.dart';

class _StatCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label, required this.value,
    required this.icon, required this.color, required this.gradientColors,
  });
}

class CustomersListPage extends StatefulWidget {
  const CustomersListPage({Key? key}) : super(key: key);
  @override
  State<CustomersListPage> createState() => _CustomersListPageState();
}

class _CustomersListPageState extends State<CustomersListPage> {
  static const Color _navy   = Color(0xFF1e3a8a);
  static const Color _purple = Color(0xFF9B59B6);
  static const Color _green  = Color(0xFF27AE60);
  static const Color _blue   = Color(0xFF2980B9);

  List<CustomerData> _customers = [];
  List<CustomerData> _filtered  = [];
  Map<String, dynamic>? _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  String _selectedStatus = 'All';
  final List<String> _statusFilters = ['All','Active','Inactive','Blocked','Lead','Closed'];
  String _selectedType = 'All Types';
  final List<String> _typeFilters = ['All Types','Individual','Organization','Vendor','Others'];
  String _selectedStatusAdv = 'All Statuses';
  final List<String> _statusAdvFilters = ['All Statuses','Active','Inactive','Blocked','Lead','Closed'];
  String _selectedTier = 'All Tiers';
  final List<String> _tierFilters = ['All Tiers','Gold Tier','Silver Tier','Bronze Tier','Platinum Tier'];
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showAdvancedFilters = false;

  String _sortBy = 'createdDate';
  bool   _sortAsc = false;
  final List<String> _sortOptions = ['Name','Company Name','Email','Phone','Created Date','Last Modified'];

  int _currentPage  = 1;
  int _totalPages   = 1;
  final int _itemsPerPage = 20;

  Set<int> _selectedRows = {};
  bool _selectAll = false;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _searchController.addListener(_applyFiltersAndSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await BillingCustomersService.getAllCustomers(
        sortBy: _getSortField(_sortBy),
        sortOrder: _sortAsc ? 'asc' : 'desc',
        limit: 1000,
      );
      if (result['success'] == true) {
        final data = result['data'];
        setState(() {
          _customers = (data['customers'] as List).map((j) => CustomerData.fromJson(j)).toList();
          _stats     = data['statistics'];
          _isLoading = false;
        });
        _applyFiltersAndSearch();
      } else {
        throw Exception(result['message'] ?? 'Failed to load customers');
      }
    } on BillingCustomersException catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toUserMessage(); });
      _showError(e.toUserMessage());
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
      _showError('Failed to load customers. Please check your connection.');
    }
  }

  String _getSortField(String s) {
    switch (s) {
      case 'Name':          return 'customerDisplayName';
      case 'Company Name':  return 'companyRegistration';
      case 'Email':         return 'primaryEmail';
      case 'Phone':         return 'primaryPhone';
      case 'Last Modified': return 'lastModifiedDate';
      default:              return 'createdDate';
    }
  }

  void _applyFiltersAndSearch() {
    setState(() {
      _filtered = _customers.where((c) {
        if (_searchController.text.isNotEmpty) {
          final q = _searchController.text.toLowerCase();
          if (!c.name.toLowerCase().contains(q) &&
              !c.companyName.toLowerCase().contains(q) &&
              !c.email.toLowerCase().contains(q) &&
              !c.workPhone.contains(q)) return false;
        }
        if (_fromDate != null && c.createdDate.isBefore(_fromDate!)) return false;
        if (_toDate   != null && c.createdDate.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
        if (_selectedStatus != 'All' && c.status != _selectedStatus) return false;
        if (_selectedType != 'All Types' && c.type != _selectedType) return false;
        if (_selectedStatusAdv != 'All Statuses' && c.status != _selectedStatusAdv) return false;
        if (_selectedTier != 'All Tiers') {
          final tierName = _selectedTier.replaceAll(' Tier', '');
          if (c.tier != tierName) return false;
        }
        return true;
      }).toList();
      _totalPages = (_filtered.length / _itemsPerPage).ceil().clamp(1, 999);
      if (_currentPage > _totalPages) _currentPage = _totalPages;
      _selectedRows.clear();
      _selectAll = false;
    });
  }

  List<CustomerData> get _currentPageItems {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end   = (start + _itemsPerPage).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus    = 'All';
      _selectedType      = 'All Types';
      _selectedStatusAdv = 'All Statuses';
      _selectedTier      = 'All Tiers';
      _fromDate          = null;
      _toDate            = null;
      _currentPage       = 1;
      _showAdvancedFilters = false;
    });
    _applyFiltersAndSearch();
  }

  bool get _hasDateFilters => _fromDate != null || _toDate != null;
  bool get _hasAnyFilter =>
      _selectedStatus != 'All' || _selectedType != 'All Types' ||
      _selectedStatusAdv != 'All Statuses' || _selectedTier != 'All Tiers' ||
      _hasDateFilters || _searchController.text.isNotEmpty;

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedRows = Set.from(List.generate(_currentPageItems.length, (i) => i));
      } else {
        _selectedRows.clear();
      }
    });
  }

  void _toggleRowSelection(int index) {
    setState(() {
      if (_selectedRows.contains(index)) {
        _selectedRows.remove(index);
        _selectAll = false;
      } else {
        _selectedRows.add(index);
        if (_selectedRows.length == _currentPageItems.length) _selectAll = true;
      }
    });
  }

  void _navigateToNewCustomer() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NewCustomerPage()));
    if (result == true) _loadCustomers();
  }

  void _navigateToEditCustomer(CustomerData c) async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewCustomerPage(customerId: c.id)));
    if (result == true) _loadCustomers();
  }

  Future<void> _viewCustomerDetails(CustomerData c) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: c)),
    ).then((result) { if (result == true) _loadCustomers(); });
  }

  Future<void> _deleteCustomer(CustomerData c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Customer', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${c.name}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      setState(() => _isLoading = true);
      final result = await BillingCustomersService.deleteCustomer(c.id);
      if (result['success'] == true) {
        _showSuccess('Customer deleted successfully');
        _loadCustomers();
      } else {
        throw Exception(result['message'] ?? 'Failed to delete customer');
      }
    } on BillingCustomersException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toUserMessage());
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to delete customer: ${e.toString()}');
    }
  }

  // ── Export (identical to original logic) ──────────────────────────────────

  void _handleExport() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export Customers', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export ${_selectedRows.isEmpty ? _filtered.length : _selectedRows.length} customers',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text('Select export format:'),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Color(0xFF27AE60)),
              title: const Text('Excel (XLSX)'),
              onTap: () { Navigator.pop(context); _exportToExcel(); },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF'),
              onTap: () { Navigator.pop(context); _exportToPDF(); },
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Color(0xFF2980B9)),
              title: const Text('CSV'),
              onTap: () { Navigator.pop(context); _exportToCSV(); },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    try {
      if (_filtered.isEmpty) { _showError('No customers to export'); return; }
      _showSuccess('Preparing Excel export...');
      final List<List<dynamic>> csvData = [
        ['Customer Name','Company Name','Type','Status','Tier','Primary Email','Work Phone','Created Date'],
        ..._filtered.map((c) => [
          c.name, c.companyName, c.type, c.status, c.tier,
          c.email, c.workPhone,
          DateFormat('dd/MM/yyyy').format(c.createdDate),
        ]),
      ];
      await ExportHelper.exportToExcel(data: csvData, filename: 'customers');
      _showSuccess('✅ Excel file downloaded with ${_filtered.length} customers!');
    } catch (e) { _showError('Failed to export: $e'); }
  }

  Future<void> _exportToPDF() async {
    try {
      if (_filtered.isEmpty) { _showError('No customers to export'); return; }
      _showSuccess('Preparing PDF export...');
      final List<List<dynamic>> pdfData = _filtered
          .map((c) => [c.name, c.companyName, c.email, c.workPhone, c.status])
          .toList();
      await ExportHelper.exportToPDF(
        title: 'Customers Report',
        headers: ['Name','Company','Email','Phone','Status'],
        data: pdfData,
        filename: 'customers',
      );
      _showSuccess('✅ PDF file downloaded with ${_filtered.length} customers!');
    } catch (e) { _showError('Failed to export PDF: $e'); }
  }

  Future<void> _exportToCSV() async { await _exportToExcel(); }

  // ── Import — opens BulkImportCustomersDialog ──────────────────────────────

  void _handleBulkImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportCustomersDialog(onImportComplete: _loadCustomers),
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _sortOptions.map((opt) => RadioListTile<String>(
            title: Text(opt),
            value: opt,
            groupValue: _sortBy,
            onChanged: (v) {
              setState(() => _sortBy = v!);
              Navigator.pop(context);
              _loadCustomers();
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!,
      ),
    );
    if (picked != null) { setState(() => _fromDate = picked); _applyFiltersAndSearch(); }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!,
      ),
    );
    if (picked != null) { setState(() => _toDate = picked); _applyFiltersAndSearch(); }
  }

  void _clearDateFilters() {
    setState(() { _fromDate = null; _toDate = null; });
    _applyFiltersAndSearch();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8), Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8), Text(message),
      ]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Customers'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopBar(),
            if (_showAdvancedFilters) _buildAdvancedFiltersBar(),
            _buildStatsCards(),
            _isLoading
                ? const SizedBox(height: 400,
                    child: Center(child: CircularProgressIndicator(color: _navy)))
                : _errorMessage != null
                    ? SizedBox(height: 400, child: _buildErrorState())
                    : _filtered.isEmpty
                        ? SizedBox(height: 400, child: _buildEmptyState())
                        : _buildCustomersTable(),
            if (!_isLoading && _filtered.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

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
        final w = c.maxWidth;
        if (w >= 1100) return _topBarDesktop();
        if (w >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 240),
    const SizedBox(width: 10),
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _selectFromDate),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _selectToDate),
    if (_hasDateFilters) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, _clearDateFilters, tooltip: 'Clear Dates', color: Colors.red[600]!, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
        tooltip: 'Advanced Filters',
        color: _showAdvancedFilters ? _navy : const Color(0xFF7F8C8D),
        bg: _showAdvancedFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
    const SizedBox(width: 6),
    _iconBtn(Icons.sort, _showSortDialog, tooltip: 'Sort'),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : () { _loadCustomers(); _showSuccess('List refreshed'); }, tooltip: 'Refresh'),
    const Spacer(),
    _actionBtn('New Customer', Icons.add_rounded, _navy, _navigateToNewCustomer),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleBulkImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _blue, _filtered.isEmpty ? null : _handleExport),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 200),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _selectFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _selectToDate),
      if (_hasDateFilters) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, _clearDateFilters, tooltip: 'Clear Dates', color: Colors.red[600]!, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
          tooltip: 'Filters',
          color: _showAdvancedFilters ? _navy : const Color(0xFF7F8C8D),
          bg: _showAdvancedFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : () { _loadCustomers(); _showSuccess('List refreshed'); }, tooltip: 'Refresh'),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Customer', Icons.add_rounded, _navy, _navigateToNewCustomer),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleBulkImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _blue, _filtered.isEmpty ? null : _handleExport),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _navigateToNewCustomer),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _selectFromDate),
        const SizedBox(width: 6),
        _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _selectToDate),
        if (_hasDateFilters) ...[
          const SizedBox(width: 6),
          _iconBtn(Icons.close, _clearDateFilters, tooltip: 'Clear', color: Colors.red[600]!, bg: Colors.red[50]!),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
            tooltip: 'Filters',
            color: _showAdvancedFilters ? _navy : const Color(0xFF7F8C8D),
            bg: _showAdvancedFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _isLoading ? null : () { _loadCustomers(); _showSuccess('List refreshed'); }, tooltip: 'Refresh'),
        const SizedBox(width: 6),
        _compactBtn('Import', _purple, _isLoading ? null : _handleBulkImport),
        const SizedBox(width: 6),
        _compactBtn('Export', _blue, _filtered.isEmpty ? null : _handleExport),
      ]),
    ),
  ]);

  Widget _buildAdvancedFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: LayoutBuilder(builder: (_, c) {
        final isNarrow = c.maxWidth < 700;
        final typeDD = _advDropdown(_selectedType, _typeFilters,
            (v) { setState(() { _selectedType = v!; _currentPage = 1; }); _applyFiltersAndSearch(); });
        final statusDD = _advDropdown(_selectedStatusAdv, _statusAdvFilters,
            (v) { setState(() { _selectedStatusAdv = v!; _currentPage = 1; }); _applyFiltersAndSearch(); });
        final tierDD = _advDropdown(_selectedTier, _tierFilters,
            (v) { setState(() { _selectedTier = v!; _currentPage = 1; }); _applyFiltersAndSearch(); });
        final clearBtn = TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.clear, size: 16),
          label: const Text('Clear All'),
          style: TextButton.styleFrom(foregroundColor: Colors.red[600]),
        );
        if (isNarrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Advanced Filters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
            const SizedBox(height: 10),
            typeDD, const SizedBox(height: 8),
            statusDD, const SizedBox(height: 8),
            tierDD, const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: clearBtn),
          ]);
        }
        return Row(children: [
          const Text('Filters:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(width: 12),
          Expanded(child: typeDD), const SizedBox(width: 10),
          Expanded(child: statusDD), const SizedBox(width: 10),
          Expanded(child: tierDD), const SizedBox(width: 10),
          if (_hasAnyFilter) clearBtn,
        ]);
      }),
    );
  }

  Widget _advDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50)),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Customers' : s))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFiltersAndSearch(); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search by name, email, phone, company...',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchController.clear(); setState(() => _currentPage = 1); _applyFiltersAndSearch(); })
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

  Widget _dateChip({required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? _navy.withOpacity(0.08) : const Color(0xFFF7F9FC),
          border: Border.all(color: isActive ? _navy : const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today, size: 15, color: isActive ? _navy : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: isActive ? _navy : Colors.grey[600])),
        ]),
      ),
    );
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

  Widget _buildStatsCards() {
    final total    = _customers.length;
    final active   = _customers.where((c) => c.status == 'Active').length;
    final inactive = _customers.where((c) => c.status == 'Inactive' || c.status == 'Blocked').length;
    final leads    = _customers.where((c) => c.status == 'Lead').length;
    final cards = [
      _StatCardData(label: 'Total Customers', value: total.toString(), icon: Icons.people_alt_rounded, color: _navy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Active Customers', value: active.toString(), icon: Icons.check_circle_outline, color: _green, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Inactive / Blocked', value: inactive.toString(), icon: Icons.block_outlined, color: const Color(0xFFE74C3C), gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'Leads', value: leads.toString(), icon: Icons.person_search_outlined, color: const Color(0xFFE67E22), gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
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

  Widget _buildStatCard(_StatCardData data, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [data.gradientColors[0].withOpacity(0.15), data.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: data.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: LinearGradient(colors: data.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                child: Icon(data.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 10),
              Text(data.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(data.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: data.color), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: data.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: data.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(data.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(data.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(data.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: data.color), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
    );
  }

  Widget _buildCustomersTable() {
    final items = _currentPageItems;
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
                  headingRowHeight: 52, dataRowMinHeight: 58, dataRowMaxHeight: 72,
                  dataTextStyle: const TextStyle(fontSize: 14),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 18, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E), onChanged: _toggleSelectAll))),
                    const DataColumn(label: Text('DATE')),
                    const DataColumn(label: Text('CUSTOMER NAME')),
                    const DataColumn(label: Text('COMPANY / REG.')),
                    const DataColumn(label: Text('EMAIL')),
                    const DataColumn(label: Text('PHONE')),
                    const DataColumn(label: Text('STATUS')),
                    const DataColumn(label: Text('TYPE')),
                    const DataColumn(label: Text('TIER')),
                    const DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: items.asMap().entries.map((e) => _buildCustomerRow(e.key, e.value)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildCustomerRow(int index, CustomerData c) {
    final isSelected = _selectedRows.contains(index);
    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith((states) {
        if (isSelected) return _navy.withOpacity(0.06);
        if (states.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(Checkbox(value: isSelected, onChanged: (_) => _toggleRowSelection(index))),
        DataCell(SizedBox(width: 110, child: Text(DateFormat('dd MMM yyyy').format(c.createdDate), style: TextStyle(fontSize: 13, color: Colors.grey[700])))),
        DataCell(SizedBox(width: 170, child: InkWell(
          onTap: () => _navigateToEditCustomer(c),
          child: Row(children: [
            Container(width: 30, height: 30, margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: _navy.withOpacity(0.10), shape: BoxShape.circle),
                child: Center(child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?', style: const TextStyle(color: _navy, fontWeight: FontWeight.bold, fontSize: 13)))),
            Expanded(child: Text(c.name.isNotEmpty ? c.name : '-', overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, decoration: TextDecoration.underline))),
          ]),
        ))),
        DataCell(SizedBox(width: 170, child: Text(
          (c.type == 'Organization' || c.type == 'Vendor') && c.companyName.isNotEmpty ? c.companyName : '—',
          overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600])))),
        DataCell(SizedBox(width: 190, child: Text(c.email, overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(width: 130, child: Text(c.workPhone))),
        DataCell(SizedBox(width: 100, child: _buildStatusBadge(c.status))),
        DataCell(SizedBox(width: 110, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: _navy.withOpacity(0.06), borderRadius: BorderRadius.circular(6)),
          child: Text(c.type, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _navy), textAlign: TextAlign.center),
        ))),
        DataCell(SizedBox(width: 80, child: _buildTierBadge(c.tier))),
        DataCell(SizedBox(width: 100, child: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (value) async {
            switch (value) {
              case 'view':   await _viewCustomerDetails(c);  break;
              case 'edit':   _navigateToEditCustomer(c);     break;
              case 'delete': await _deleteCustomer(c);       break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'view', child: ListTile(leading: Icon(Icons.visibility_outlined, size: 17, color: Color(0xFF1e3a8a)), title: Text('View Details'), contentPadding: EdgeInsets.zero)),
            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined, size: 17, color: Color(0xFF2980B9)), title: Text('Edit'), contentPadding: EdgeInsets.zero)),
            const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, size: 17, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero)),
          ],
        ))),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    const statusColors = <String, List<Color>>{
      'Active':   [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'Inactive': [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'Blocked':  [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'Lead':     [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'Closed':   [Color(0xFFFEF3C7), Color(0xFFB45309)],
    };
    final c = statusColors[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _buildTierBadge(String tier) {
    const tierColors = <String, Color>{'Gold': Color(0xFFD4AC0D), 'Platinum': Color(0xFF7D3C98), 'Silver': Color(0xFF616A6B), 'Bronze': Color(0xFFCA6F1E)};
    return Text(tier.isNotEmpty ? tier : '—', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tierColors[tier] ?? const Color(0xFF64748B)));
  }

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) { pages = List.generate(_totalPages, (i) => i + 1); }
    else {
      final start = (_currentPage - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: LayoutBuilder(builder: (_, c) {
        final isNarrow = c.maxWidth < 500;
        return Wrap(
          alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
          children: [
            Text(
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _filtered.length)} of ${_filtered.length}'
              '${_filtered.length != _customers.length ? ' (filtered from ${_customers.length})' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); _applyFiltersAndSearch(); }),
              const SizedBox(width: 4),
              if (!isNarrow && pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))),
              ],
              ...pages.map((p) => _pageNumBtn(p)),
              if (!isNarrow && pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _applyFiltersAndSearch(); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _applyFiltersAndSearch(); } },
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

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle), child: Icon(Icons.people_outline, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Customers Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasAnyFilter ? 'Try adjusting your filters' : 'Start by adding your first customer', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasAnyFilter ? _clearFilters : _navigateToNewCustomer,
        icon: Icon(_hasAnyFilter ? Icons.filter_list_off : Icons.add),
        label: Text(_hasAnyFilter ? 'Clear Filters' : 'Add Customer', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle), child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Customers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(_errorMessage ?? 'An unknown error occurred', style: TextStyle(fontSize: 14, color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _loadCustomers, icon: const Icon(Icons.refresh),
        label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }
} // ← END _CustomersListPageState

// =============================================================================
//  BULK IMPORT CUSTOMERS DIALOG — full original StatefulWidget with all fields
// =============================================================================

class BulkImportCustomersDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  const BulkImportCustomersDialog({Key? key, required this.onImportComplete}) : super(key: key);
  @override
  State<BulkImportCustomersDialog> createState() => _BulkImportCustomersDialogState();
}

class _BulkImportCustomersDialogState extends State<BulkImportCustomersDialog> {
  bool isDownloading = false;
  bool isUploading   = false;
  String? uploadedFileName;
  List<Map<String, dynamic>>? importResults;

  Future<void> _downloadTemplate() async {
    setState(() => isDownloading = true);
    try {
      final List<List<dynamic>> templateData = [
        // Headers — full 21 columns identical to original
        [
          'Customer Type* (Individual/Organization/Vendor/Others)',
          'Customer Display Name*',
          'Primary Contact Person',
          'Primary Email*',
          'Primary Phone*',
          'Alternate Phone',
          'Address Line 1*',
          'Address Line 2',
          'City*',
          'State*',
          'Postal Code',
          'Country*',
          'Company Registration',
          'PAN Number',
          'GST Number',
          'TAN Number',
          'Industry Type',
          'Employee Strength',
          'Customer Status* (Active/Inactive/Blocked/Lead/Closed)',
          'Customer Tier (Gold/Silver/Bronze/Platinum)',
          'Sales Territory*',
        ],
        // Example row
        [
          'Organization', 'Acme Corporation', 'John Doe', 'john@acme.com', '9876543210', '9876543211',
          '123 Business Street', 'Suite 100', 'Bangalore', 'Karnataka', '560001', 'India',
          'U12345KA2020PTC123456', 'ABCDE1234F', '29ABCDE1234F1Z5', 'ABCD12345E',
          'IT & Software', '50', 'Active', 'Gold', 'Bangalore',
        ],
        // Instructions
        [
          'INSTRUCTIONS:',
          '1. Fields marked with * are required',
          '2. Customer Type: Individual, Organization, Vendor, or Others',
          '3. Phone should be 10 digits',
          '4. Email must be valid format',
          '5. GST Number required for Organization/Vendor',
          '6. Delete this instruction row before uploading',
        ],
      ];
      await ExportHelper.exportToExcel(data: templateData, filename: 'customers_import_template');
      setState(() => isDownloading = false);
      _showSuccess('Template downloaded successfully!');
    } catch (e) {
      setState(() => isDownloading = false);
      _showError('Failed to download template: ${e.toString()}');
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      setState(() { uploadedFileName = file.name; isUploading = true; importResults = null; });

      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('Failed to read file');

      List<List<dynamic>> rows;
      final ext = file.extension?.toLowerCase() ?? '';
      if (ext == 'csv') {
        rows = _parseCSV(bytes);
      } else if (ext == 'xlsx' || ext == 'xls') {
        rows = _parseExcel(bytes);
      } else {
        throw Exception('Unsupported file format');
      }
      if (rows.length < 2) throw Exception('File must contain at least header and one data row');

      final List<Map<String, dynamic>> customersToImport = [];
      final List<String> errors = [];

      for (int i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          if (row.isEmpty || row[0] == null || row[0].toString().trim().isEmpty) continue;

          final customerType         = _sv(row, 0);
          final customerDisplayName  = _sv(row, 1);
          final primaryContactPerson = _sv(row, 2);
          final primaryEmail         = _sv(row, 3);
          final primaryPhone         = _parsePhone(_gv(row, 4));
          final alternatePhone       = _parsePhone(_gv(row, 5));
          final addressLine1         = _sv(row, 6);
          final addressLine2         = _sv(row, 7);
          final city                 = _sv(row, 8);
          final state                = _sv(row, 9);
          final postalCode           = _sv(row, 10);
          final country              = _sv(row, 11, 'India');
          final companyRegistration  = _sv(row, 12);
          final panNumber            = _sv(row, 13);
          final gstNumber            = _sv(row, 14);
          final tanNumber            = _sv(row, 15);
          final industryType         = _sv(row, 16);
          final employeeStrength     = _sv(row, 17);
          final customerStatus       = _sv(row, 18, 'Active');
          final customerTier         = _sv(row, 19);
          final salesTerritory       = _sv(row, 20);

          final rowErrors = <String>[];
          if (customerType.isEmpty)        rowErrors.add('Customer Type required');
          if (customerDisplayName.isEmpty) rowErrors.add('Customer Name required');
          if (primaryEmail.isEmpty)        rowErrors.add('Email required');
          if (primaryPhone.isEmpty)        rowErrors.add('Phone required');
          if (addressLine1.isEmpty)        rowErrors.add('Address required');
          if (city.isEmpty)                rowErrors.add('City required');
          if (state.isEmpty)               rowErrors.add('State required');
          if (salesTerritory.isEmpty)      rowErrors.add('Sales Territory required');
          if ((customerType == 'Organization' || customerType == 'Vendor') && gstNumber.isEmpty) {
            rowErrors.add('GST Number required for B2B customers');
          }
          if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(", ")}'); continue; }

          customersToImport.add({
            'customerType':         customerType,
            'customerDisplayName':  customerDisplayName,
            'primaryContactPerson': primaryContactPerson,
            'primaryEmail':         primaryEmail,
            'primaryPhone':         primaryPhone,
            'alternatePhone':       alternatePhone,
            'addressLine1':         addressLine1,
            'addressLine2':         addressLine2,
            'city':                 city,
            'state':                state,
            'postalCode':           postalCode,
            'country':              country,
            'companyRegistration':  companyRegistration,
            'panNumber':            panNumber,
            'gstNumber':            gstNumber,
            'tanNumber':            tanNumber,
            'industryType':         industryType,
            'employeeStrength':     employeeStrength.isNotEmpty ? int.tryParse(employeeStrength) : null,
            'customerStatus':       customerStatus,
            'customerTier':         customerTier,
            'salesTerritory':       salesTerritory,
          });
        } catch (e) { errors.add('Row ${i + 1}: ${e.toString()}'); }
      }

      if (customersToImport.isEmpty) throw Exception('No valid customer data found');

      // Confirm dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirm Import'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Found ${customersToImport.length} customer(s) to import.'),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('${errors.length} row(s) skipped:', style: const TextStyle(color: Colors.red)),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12))),
              ),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() { isUploading = false; uploadedFileName = null; });
        return;
      }

      final importResult = await BillingCustomersService.bulkImportCustomers(customersToImport);
      setState(() {
        isUploading = false;
        importResults = [{
          'success': importResult['data']['successCount'],
          'failed':  importResult['data']['failedCount'],
          'total':   importResult['data']['totalProcessed'],
          'errors':  importResult['data']['errors'] ?? [],
        }];
      });
      if (importResult['success'] == true) {
        _showSuccess('Import completed!');
        widget.onImportComplete();
      }
    } catch (e) {
      setState(() { isUploading = false; uploadedFileName = null; });
      _showError('Failed to import: ${e.toString()}');
    }
  }

  String _parsePhone(dynamic value) {
    if (value == null) return '';
    final s = value.toString().trim();
    if (s.toUpperCase().contains('E')) {
      try { return double.parse(s).round().toString(); } catch (_) {}
    }
    return s;
  }

  dynamic _gv(List<dynamic> row, int i) => i < row.length ? row[i] : null;

  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
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

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
return Dialog(
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  child: Container(
    width: MediaQuery.of(context).size.width > 600
        ? 560
        : MediaQuery.of(context).size.width * 0.92,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF9B59B6).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.upload_file, color: Color(0xFF9B59B6), size: 24),
            ),
            const SizedBox(width: 14),
            const Text('Import Customers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),
          _importStep(
            step: '1', color: const Color(0xFF2980B9), icon: Icons.download,
            title: 'Download Template',
            subtitle: 'Get the CSV template with required column format and sample data.',
            buttonLabel: isDownloading ? 'Downloading...' : 'Download Template',
            onPressed: isDownloading || isUploading ? null : _downloadTemplate,
          ),
          const SizedBox(height: 16),
          _importStep(
            step: '2', color: const Color(0xFF27AE60), icon: Icons.upload,
            title: 'Upload Filled File',
            subtitle: 'Fill in the template and upload to import your customers.',
            buttonLabel: isUploading ? 'Uploading...' : 'Select File',
            onPressed: isDownloading || isUploading ? null : _uploadFile,
          ),
          if (importResults != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 18),
                  const SizedBox(width: 8),
                  Text('Successfully imported: ${importResults![0]['success']}'),
                ]),
                if ((importResults![0]['failed'] ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.cancel, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Text('Failed: ${importResults![0]['failed']}', style: const TextStyle(color: Colors.red)),
                  ]),
                ],
              ]),
            ),
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
    final circle = Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
    );
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        disabledBackgroundColor: color.withOpacity(0.5),
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
        return Row(children: [
          circle, const SizedBox(width: 14),
          Expanded(child: textBlock),
          const SizedBox(width: 12),
          button,
        ]);
      }),
    );
  }
}


// =============================================================================
//  CUSTOMER DETAILS DIALOG — identical to original with full documents section
// =============================================================================

class CustomerDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> customerData;
  const CustomerDetailsDialog({Key? key, required this.customerData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final documents = (customerData['uploadedDocuments'] as List?) ?? [];
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width:  MediaQuery.of(context).size.width  * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person, color: Color(0xFF1e3a8a), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customerData['customerDisplayName'] ?? 'Unknown',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text(customerData['customerId'] ?? '', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ])),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 32),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildSection('Basic Information', [
              _buildInfoRow('Customer Type',   customerData['customerType']),
              _buildInfoRow('Display Name',    customerData['customerDisplayName']),
              _buildInfoRow('Primary Email',   customerData['primaryEmail']),
              _buildInfoRow('Primary Phone',   customerData['primaryPhone']),
              _buildInfoRow('Alternate Phone', customerData['alternatePhone']),
            ]),
            const SizedBox(height: 24),
            _buildSection('Address Information', [
              _buildInfoRow('Address Line 1', customerData['addressLine1']),
              _buildInfoRow('Address Line 2', customerData['addressLine2']),
              _buildInfoRow('City',        customerData['city']),
              _buildInfoRow('State',       customerData['state']),
              _buildInfoRow('Postal Code', customerData['postalCode']),
              _buildInfoRow('Country',     customerData['country']),
            ]),
            const SizedBox(height: 24),
            if (customerData['customerType'] == 'Organization' || customerData['customerType'] == 'Vendor') ...[
              _buildSection('Company Details', [
                _buildInfoRow('Company Registration', customerData['companyRegistration']),
                _buildInfoRow('PAN Number',           customerData['panNumber']),
                _buildInfoRow('GST Number',           customerData['gstNumber']),
                _buildInfoRow('TAN Number',           customerData['tanNumber']),
                _buildInfoRow('Industry Type',        customerData['industryType']),
                _buildInfoRow('Employee Strength',    customerData['employeeStrength']?.toString()),
              ]),
              const SizedBox(height: 24),
            ],
            _buildSection('Status & Categorization', [
              _buildInfoRow('Customer Status', customerData['customerStatus']),
              _buildInfoRow('Customer Tier',   customerData['customerTier']),
              _buildInfoRow('Sales Territory', customerData['salesTerritory']),
              if (customerData['tags'] != null && (customerData['tags'] as List).isNotEmpty)
                _buildInfoRow('Tags', (customerData['tags'] as List).join(', ')),
            ]),
            if (documents.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildDocumentsSection(context, documents),
            ],
          ]))),
          const Divider(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ]),
        ]),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
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

  Widget _buildInfoRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 180, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2C3E50), fontSize: 14))),
        Expanded(child: Text(value.toString(), style: TextStyle(color: Colors.grey[800], fontSize: 14))),
      ]),
    );
  }

  Widget _buildDocumentsSection(BuildContext context, List documents) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Uploaded Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Column(children: documents.map<Widget>((doc) => _buildDocumentItem(context, doc)).toList()),
      ),
    ]);
  }

  Widget _buildDocumentItem(BuildContext context, Map<String, dynamic> doc) {
    final fileName   = doc['originalName'] ?? doc['fileName'] ?? 'Unknown';
    final category   = doc['category'] ?? 'Other Documents';
    final fileSize   = doc['fileSize'] != null ? '${(doc['fileSize'] / 1024).toStringAsFixed(1)} KB' : '';
    final uploadedAt = _formatDate(doc['uploadedAt']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey[300]!)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fileName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text('$category • $fileSize', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (uploadedAt.isNotEmpty) Text('Uploaded: $uploadedAt', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ])),
        IconButton(
          icon: const Icon(Icons.download, color: Color(0xFF1e3a8a)),
          tooltip: 'Download',
          onPressed: () => _downloadDocument(context, doc),
        ),
      ]),
    );
  }

  void _downloadDocument(BuildContext context, Map<String, dynamic> doc) async {
    final filePath = doc['filePath'] as String?;
    final fileName = doc['originalName'] ?? doc['fileName'] ?? 'document';
    if (filePath == null || filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document path not found'), backgroundColor: Colors.red));
      return;
    }
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/$filePath');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading $fileName...'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)));
      } else { throw Exception('Could not launch download URL'); }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to download: ${e.toString()}'), backgroundColor: Colors.red, duration: const Duration(seconds: 3)));
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final dt = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) { return date.toString(); }
  }
}


// =============================================================================
//  DATA MODELS — identical to original (all fields + toJson preserved)
// =============================================================================

class CustomerData {
  final String id;
  final String name;
  final String companyName;
  final String email;
  final String workPhone;
  final String status;
  final String type;
  final String tier;
  final DateTime createdDate;
  final List<UploadedDocument> uploadedDocuments;
  final int documentCount;

  CustomerData({
    required this.id, required this.name, required this.companyName,
    required this.email, required this.workPhone, required this.status,
    required this.type, required this.tier, required this.createdDate,
    this.uploadedDocuments = const [], this.documentCount = 0,
  });

  factory CustomerData.fromJson(Map<String, dynamic> json) {
    List<UploadedDocument> docs = [];
    if (json['uploadedDocuments'] != null) {
      docs = (json['uploadedDocuments'] as List).map((d) => UploadedDocument.fromJson(d)).toList();
    }
    return CustomerData(
      id:          json['_id'] ?? json['customerId'] ?? '',
      name:        json['customerDisplayName'] ?? '',
      companyName: json['companyRegistration'] ?? '',
      email:       json['primaryEmail'] ?? '',
      workPhone:   json['primaryPhone'] ?? '',
      status:      json['customerStatus'] ?? 'Active',
      type:        json['customerType'] ?? 'Individual',
      tier:        json['customerTier'] ?? 'Silver',
      createdDate: json['createdDate'] != null ? DateTime.parse(json['createdDate']) : DateTime.now(),
      uploadedDocuments: docs,
      documentCount: docs.length,
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id, 'customerDisplayName': name, 'companyRegistration': companyName,
    'primaryEmail': email, 'primaryPhone': workPhone, 'customerStatus': status,
    'customerType': type, 'customerTier': tier, 'createdDate': createdDate.toIso8601String(),
    'uploadedDocuments': uploadedDocuments.map((d) => d.toJson()).toList(),
  };
}

class UploadedDocument {
  final String category, fileName, originalName, filePath;
  final int fileSize;
  final String? fileExtension;
  final DateTime uploadedAt;
  final String? uploadedBy;

  UploadedDocument({
    required this.category, required this.fileName, required this.originalName,
    required this.filePath, required this.fileSize, this.fileExtension,
    required this.uploadedAt, this.uploadedBy,
  });

  factory UploadedDocument.fromJson(Map<String, dynamic> json) {
    return UploadedDocument(
      category:     json['category']     ?? 'Other Documents',
      fileName:     json['fileName']     ?? '',
      originalName: json['originalName'] ?? '',
      filePath:     json['filePath']     ?? '',
      fileSize:     json['fileSize']     ?? 0,
      fileExtension: json['fileExtension'],
      uploadedAt: json['uploadedAt'] != null ? DateTime.parse(json['uploadedAt']) : DateTime.now(),
      uploadedBy: json['uploadedBy'],
    );
  }

  Map<String, dynamic> toJson() => {
    'category': category, 'fileName': fileName, 'originalName': originalName,
    'filePath': filePath, 'fileSize': fileSize, 'fileExtension': fileExtension,
    'uploadedAt': uploadedAt.toIso8601String(), 'uploadedBy': uploadedBy,
  };

  String get fileSizeFormatted {
    if (fileSize < 1024)        return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}