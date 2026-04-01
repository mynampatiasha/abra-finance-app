// ============================================================================
// FINANCE ERP USERS SCREEN — Full Recurring Invoice UI Pattern
// ============================================================================
// File: lib/screens/erp_users_management_screen.dart
// UI matches recurring_invoices_list_page.dart:
//  - AppTopBar
//  - 3-breakpoint top bar (Desktop ≥1100 / Tablet 700–1100 / Mobile <700)
//  - 4 gradient stat cards, h-scroll on mobile
//  - Dark navy #0D1B3E DataTable, drag-to-scroll at ALL screen sizes
//  - Ellipsis pagination (client-side)
//  - Share + WhatsApp + Permissions + Edit + Ticket + Remove — all direct on row
//  - NO mobile card layout — table with horizontal scroll everywhere
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/finance_secure_storage.dart';
import '../../data/services/finance_auth_service.dart';
import '../../core/permissions_finance.dart';
import '../../../../core/services/tms_service.dart';
import '../billing/app_top_bar.dart';

// ── colour palette ────────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF00897B);

const Color _navyDark  = Color(0xFF0D1B3E);
const Color _navyMid   = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);

// ── stat card data ────────────────────────────────────────────────────────────
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

// ── Model ─────────────────────────────────────────────────────────────────────
class FinanceBillingUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String status;
  final Map<String, dynamic> permissions;
  final List<dynamic> organizations;

  const FinanceBillingUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.permissions,
    required this.organizations,
  });

  factory FinanceBillingUser.fromJson(Map<String, dynamic> j, String orgId) {
    final orgs  = List<dynamic>.from(j['organizations'] ?? []);
    final myOrg = orgs.firstWhere(
      (o) => o['orgId'] == orgId,
      orElse: () => <String, dynamic>{},
    );
    return FinanceBillingUser(
      id:            j['_id']?.toString() ?? '',
      name:          j['name']?.toString() ?? '',
      email:         j['email']?.toString() ?? '',
      phone:         j['phone']?.toString() ?? '',
      role:          myOrg['role']?.toString() ?? 'staff',
      status:        j['status']?.toString() ?? 'active',
      permissions:   Map<String, dynamic>.from(j['permissions'] ?? {}),
      organizations: orgs,
    );
  }
}

// =============================================================================
//  SCREEN
// =============================================================================

class FinanceERPUsersScreen extends StatefulWidget {
  const FinanceERPUsersScreen({super.key});

  @override
  State<FinanceERPUsersScreen> createState() => _FinanceERPUsersScreenState();
}

class _FinanceERPUsersScreenState extends State<FinanceERPUsersScreen> {

  // ── data ───────────────────────────────────────────────────────────────────
  List<FinanceBillingUser> _users    = [];
  List<FinanceBillingUser> _filtered = [];
  bool   _loading        = true;
  String _currentRole    = '';
  String _currentOrgId   = '';
  String _currentOrgName = '';

  // ── filters ────────────────────────────────────────────────────────────────
  String _selectedStatus = 'All';
  String _selectedRole   = 'All';
  bool   _showFilters    = false;
  final List<String> _statusFilters = ['All', 'active', 'inactive'];
  final List<String> _roleFilters   = ['All', 'owner', 'admin', 'accountant', 'staff'];

  // ── search ─────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();

  // ── pagination ─────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  final int _itemsPerPage = 20;

  // ── scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ── selection ──────────────────────────────────────────────────────────────
  Set<int> _selectedRows = {};
  bool _selectAll = false;

  // ===========================================================================
  @override
  void initState() {
    super.initState();
    _init();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ===========================================================================
  //  DATA
  // ===========================================================================

  Future<void> _init() async {
    _currentRole    = await FinanceSecureStorage.getRole()    ?? '';
    _currentOrgId   = await FinanceSecureStorage.getOrgId()   ?? '';
    _currentOrgName = await FinanceSecureStorage.getOrgName() ?? '';
    await _fetchUsers();
  }

  bool get _canManage =>
      _currentRole == 'owner' || _currentRole == 'admin';

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    final res = await FinanceAuthService.get('/api/finance/users');
    if (!mounted) return;
    if (res['success'] == true) {
      final raw   = List<dynamic>.from(res['data'] ?? []);
      final users = raw.map((j) => FinanceBillingUser.fromJson(
            j as Map<String, dynamic>, _currentOrgId)).toList();
      setState(() { _users = users; _loading = false; });
      _applyFilter();
    } else {
      setState(() => _loading = false);
      _showError(res['message'] ?? 'Failed to load users');
    }
  }

  Future<void> _refresh() async {
    await _fetchUsers();
    _showSuccess('Data refreshed successfully');
  }

  void _applyFilter() {
    setState(() {
      final q = _searchController.text.toLowerCase();
      _filtered = _users.where((u) {
        if (q.isNotEmpty &&
            !u.name.toLowerCase().contains(q) &&
            !u.email.toLowerCase().contains(q) &&
            !u.phone.contains(q)) return false;
        if (_selectedStatus != 'All' && u.status != _selectedStatus) return false;
        if (_selectedRole   != 'All' && u.role   != _selectedRole)   return false;
        return true;
      }).toList();
      _totalPages = (_filtered.length / _itemsPerPage).ceil().clamp(1, 9999);
      if (_currentPage > _totalPages) _currentPage = _totalPages;
      _selectedRows.clear();
      _selectAll = false;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = 'All';
      _selectedRole   = 'All';
      _currentPage    = 1;
      _showFilters    = false;
    });
    _applyFilter();
  }

  bool get _hasAnyFilter =>
      _selectedStatus != 'All' || _selectedRole != 'All' ||
      _searchController.text.isNotEmpty;

  List<FinanceBillingUser> get _currentPageItems {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end   = (start + _itemsPerPage).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  // ── selection ──────────────────────────────────────────────────────────────
  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      _selectedRows = _selectAll
          ? Set.from(List.generate(_currentPageItems.length, (i) => i))
          : {};
    });
  }

  void _toggleRow(int i) {
    setState(() {
      _selectedRows.contains(i) ? _selectedRows.remove(i) : _selectedRows.add(i);
      _selectAll = _selectedRows.length == _currentPageItems.length;
    });
  }

  // ===========================================================================
  //  ACTIONS
  // ===========================================================================

  Future<void> _shareUser(FinanceBillingUser u) async {
    final text =
        'Team Member — Abra Travels\n'
        '──────────────────────────\n'
        'Name   : ${u.name}\n'
        'Email  : ${u.email}\n'
        'Phone  : ${u.phone}\n'
        'Role   : ${u.role[0].toUpperCase()}${u.role.substring(1)}\n'
        'Status : ${u.status.toUpperCase()}\n';
    try {
      await Share.share(text, subject: 'Team Member: ${u.name}');
    } catch (e) {
      _showError('Share failed: $e');
    }
  }

  Future<void> _whatsApp(FinanceBillingUser u) async {
    final phone = u.phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) {
      _showError('Phone number not available for this user.');
      return;
    }
    final msg = Uri.encodeComponent(
      'Hello ${u.name},\n\n'
      'This is a message from Abra Travels Management.\n\n'
      'Please feel free to contact us for any queries.\n'
      'Thank you!',
    );
    final url = Uri.parse('https://wa.me/$phone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  void _openPermissions(FinanceBillingUser u) {
    FinancePermissionsScreen.showOverlay(context, userId: u.id, userName: u.name);
  }

  void _showDetails(FinanceBillingUser u) {
    showDialog(context: context, builder: (_) => _UserDetailsDialog(user: u));
  }

  void _raiseTicket(FinanceBillingUser u) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        user: u,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError:        (msg) => _showError(msg),
      ),
    );
  }

  void _confirmRemove(FinanceBillingUser u) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove User?', style: TextStyle(color: _navyDark, fontWeight: FontWeight.bold)),
        content: Text('Remove "${u.name}" from $_currentOrgName?\n\nThey will lose access to this organization.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await FinanceAuthService.delete('/api/finance/users/${u.id}');
              final msg = res['message'] ?? (res['success'] == true ? 'User removed' : 'Failed');
              if (res['success'] == true) { _showSuccess(msg); _fetchUsers(); }
              else { _showError(msg); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog({FinanceBillingUser? user}) {
    showDialog(
      context: context,
      builder: (_) => _AddEditUserDialog(
        user: user, orgName: _currentOrgName,
        onSave: (data) async {
          final res = user == null
              ? await FinanceAuthService.post('/api/finance/users', data)
              : await FinanceAuthService.put('/api/finance/users/${user.id}', data);
          final msg = res['message'] ?? (res['success'] == true ? 'Saved' : 'Failed');
          if (res['success'] == true) { _showSuccess(msg); _fetchUsers(); }
          else { _showError(msg); }
        },
      ),
    );
  }

  // ===========================================================================
  //  BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Team Members'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          if (_showFilters) _buildFiltersBar(),
          _buildStatsCards(),
          _loading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _filtered.isEmpty
                  ? SizedBox(height: 400, child: _buildEmptyState())
                  : _buildTable(),
          if (!_loading && _filtered.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // ===========================================================================
  //  TOP BAR — 3 breakpoints
  // ===========================================================================

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
    _statusDropdown(),
    const SizedBox(width: 10),
    _roleDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 240),
    const SizedBox(width: 8),
    _iconBtn(Icons.filter_list,
        () => setState(() => _showFilters = !_showFilters),
        tooltip: 'Filters',
        color: _showFilters ? _navy : const Color(0xFF7F8C8D),
        bg: _showFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _loading ? null : _refresh, tooltip: 'Refresh'),
    const Spacer(),
    if (_canManage)
      _actionBtn('Add User', Icons.person_add_rounded, _navy, () => _showAddEditDialog()),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      _roleDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _iconBtn(Icons.filter_list,
          () => setState(() => _showFilters = !_showFilters), tooltip: 'Filters'),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _loading ? null : _refresh, tooltip: 'Refresh'),
    ]),
    if (_canManage) ...[
      const SizedBox(height: 10),
      _actionBtn('Add User', Icons.person_add_rounded, _navy, () => _showAddEditDialog()),
    ],
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      if (_canManage)
        _actionBtn('Add', Icons.person_add_rounded, _navy, () => _showAddEditDialog()),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      _roleDropdown(),
      const SizedBox(width: 8),
      _iconBtn(Icons.filter_list,
          () => setState(() => _showFilters = !_showFilters)),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _loading ? null : _refresh, tooltip: 'Refresh'),
    ])),
  ]);

  // ── filters bar ────────────────────────────────────────────────────────────
  Widget _buildFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: LayoutBuilder(builder: (_, c) {
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
            _advDropdown(_selectedStatus, _statusFilters,
                (v) { setState(() { _selectedStatus = v!; _currentPage = 1; }); _applyFilter(); }),
            const SizedBox(height: 8),
            _advDropdown(_selectedRole, _roleFilters,
                (v) { setState(() { _selectedRole = v!; _currentPage = 1; }); _applyFilter(); }),
            const SizedBox(height: 8),
            if (_hasAnyFilter) Align(alignment: Alignment.centerRight, child: clearBtn),
          ]);
        }
        return Row(children: [
          const Text('Filters:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(width: 12),
          SizedBox(width: 160, child: _advDropdown(_selectedStatus, _statusFilters,
              (v) { setState(() { _selectedStatus = v!; _currentPage = 1; }); _applyFilter(); })),
          const SizedBox(width: 10),
          SizedBox(width: 160, child: _advDropdown(_selectedRole, _roleFilters,
              (v) { setState(() { _selectedRole = v!; _currentPage = 1; }); _applyFilter(); })),
          const Spacer(),
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
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All ${items == _statusFilters ? 'Status' : 'Roles'}' : s[0].toUpperCase() + s.substring(1)))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── shared top-bar widgets ─────────────────────────────────────────────────
  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(
          value: s,
          child: Text(s == 'All' ? 'All Status' : s[0].toUpperCase() + s.substring(1)),
        )).toList(),
        onChanged: (v) {
          if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFilter(); }
        },
      ),
    ),
  );

  Widget _roleDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedRole,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _roleFilters.map((s) => DropdownMenuItem(
          value: s,
          child: Text(s == 'All' ? 'All Roles' : s[0].toUpperCase() + s.substring(1)),
        )).toList(),
        onChanged: (v) {
          if (v != null) { setState(() { _selectedRole = v; _currentPage = 1; }); _applyFilter(); }
        },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search by name, email or phone…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchController.clear(); setState(() => _currentPage = 1); _applyFilter(); })
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

  Widget _iconBtn(IconData icon, VoidCallback? onTap,
      {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
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
      label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ===========================================================================
  //  STATS CARDS
  // ===========================================================================

  Widget _buildStatsCards() {
    final total    = _users.length;
    final active   = _users.where((u) => u.status == 'active').length;
    final inactive = _users.where((u) => u.status != 'active').length;
    final admins   = _users.where((u) => u.role == 'admin' || u.role == 'owner').length;

    final cards = [
      _StatCardData(label: 'Total Members', value: '$total', icon: Icons.people_outline, color: _navy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Active', value: '$active', icon: Icons.check_circle_outline, color: _green, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Inactive', value: '$inactive', icon: Icons.pause_circle_outline, color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Admins / Owners', value: '$admins', icon: Icons.admin_panel_settings_outlined, color: _purple, gradientColors: const [Color(0xFFAB68FF), Color(0xFF9B59B6)]),
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
        gradient: LinearGradient(
          colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
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

  // ===========================================================================
  //  TABLE — dark navy header, horizontal scroll at ALL screen sizes
  // ===========================================================================

  Widget _buildTable() {
    final items = _currentPageItems;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl,
          thumbVisibility: true, trackVisibility: true,
          thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl, scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                  headingRowHeight: 52, dataRowMinHeight: 64, dataRowMaxHeight: 80,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 16, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36,
                        child: Checkbox(
                          value: _selectAll,
                          fillColor: WidgetStateProperty.all(Colors.white),
                          checkColor: const Color(0xFF0D1B3E),
                          onChanged: _toggleSelectAll,
                        ))),
                    const DataColumn(label: SizedBox(width: 200, child: Text('USER'))),
                    const DataColumn(label: SizedBox(width: 210, child: Text('EMAIL'))),
                    const DataColumn(label: SizedBox(width: 140, child: Text('PHONE'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('ROLE'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('STATUS'))),
                    if (_canManage)
                      const DataColumn(label: SizedBox(width: 360, child: Text('ACTIONS'))),
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

  DataRow _buildRow(int index, FinanceBillingUser u) {
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

        // User — avatar + name
        DataCell(SizedBox(width: 200, child: InkWell(
          onTap: () => _showDetails(u),
          child: Row(children: [
            _avatar(u.name, 36),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(u.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: _navyDark, fontSize: 13, decoration: TextDecoration.underline),
                  overflow: TextOverflow.ellipsis),
              Text(u.role[0].toUpperCase() + u.role.substring(1),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ))),

        // Email
        DataCell(SizedBox(width: 210,
            child: Text(u.email, style: const TextStyle(fontSize: 13, color: _navyDark), overflow: TextOverflow.ellipsis))),

        // Phone
        DataCell(SizedBox(width: 140,
            child: Text(u.phone.isEmpty ? '—' : u.phone, style: const TextStyle(fontSize: 13, color: _navyDark), overflow: TextOverflow.ellipsis))),

        // Role
        DataCell(SizedBox(width: 120, child: _rolePill(u.role))),

        // Status
        DataCell(SizedBox(width: 100, child: _statusBadge(u.status))),

        // Actions — all direct, no popup
        if (_canManage)
          DataCell(SizedBox(width: 360, child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _rowBtn(icon: Icons.share, label: 'Share', color: _blue, onTap: () => _shareUser(u)),
              const SizedBox(width: 5),
              _rowBtn(icon: Icons.chat, label: 'WhatsApp', color: const Color(0xFF25D366), onTap: () => _whatsApp(u)),
              const SizedBox(width: 5),
              _rowBtn(icon: Icons.security_rounded, label: 'Permissions', color: _teal, onTap: () => _openPermissions(u)),
              const SizedBox(width: 5),
              _rowBtn(icon: Icons.edit_outlined, label: 'Edit', color: _orange, onTap: () => _showAddEditDialog(user: u)),
              const SizedBox(width: 5),
              _rowBtn(icon: Icons.confirmation_number_outlined, label: 'Ticket', color: _purple, onTap: () => _raiseTicket(u)),
              const SizedBox(width: 5),
              _rowBtn(icon: Icons.person_remove_outlined, label: 'Remove', color: _red, onTap: () => _confirmRemove(u)),
            ]),
          ))),
      ],
    );
  }

  Widget _rowBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.30), width: 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }

  // ===========================================================================
  //  SHARED WIDGETS
  // ===========================================================================

  Widget _avatar(String name, double size) => Container(
    width: size, height: size,
    decoration: const BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_navyMid, _navyLight]),
      shape: BoxShape.circle,
    ),
    child: Center(child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : 'U',
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.4),
    )),
  );

  Widget _rolePill(String role) {
    const Map<String, List<Color>> colors = {
      'owner':      [Color(0xFFF5F3FF), Color(0xFF7C3AED)],
      'admin':      [Color(0xFFEFF6FF), _navyLight],
      'accountant': [Color(0xFFF0FDF4), Color(0xFF059669)],
      'staff':      [Color(0xFFF3F4F6), Color(0xFF6B7280)],
    };
    final c = colors[role] ?? [const Color(0xFFF3F4F6), const Color(0xFF6B7280)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(role[0].toUpperCase() + role.substring(1),
            style: TextStyle(color: c[1], fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _statusBadge(String status) {
    final active = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? const Color(0xFF86EFAC) : const Color(0xFFFECACA)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
            color: active ? const Color(0xFF16A34A) : const Color(0xFFDC2626), shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status.toUpperCase(), style: TextStyle(
            color: active ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      ]),
    );
  }

  // ===========================================================================
  //  PAGINATION — ellipsis style
  // ===========================================================================

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
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            Text(
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _filtered.length)} of ${_filtered.length}'
              '${_filtered.length != _users.length ? ' (filtered from ${_users.length})' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1,
                  onTap: () { setState(() => _currentPage--); }),
              const SizedBox(width: 4),
              if (pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…', style: TextStyle(color: Colors.grey[400]))),
              ],
              ...pages.map(_pageNumBtn),
              if (pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…', style: TextStyle(color: Colors.grey[400]))),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages,
                  onTap: () { setState(() => _currentPage++); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) setState(() => _currentPage = page); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2), width: 34, height: 34,
        decoration: BoxDecoration(
            color: isActive ? _navy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? _navy : Colors.grey[300]!)),
        child: Center(child: Text('$page', style: TextStyle(
            fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.white : Colors.grey[700]))),
      ),
    );
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
            color: enabled ? Colors.white : Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!)),
        child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ===========================================================================
  //  EMPTY STATE
  // ===========================================================================

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.people_outline, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      Text(
        _hasAnyFilter ? 'No matching users' : 'No team members yet',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
      ),
      const SizedBox(height: 8),
      Text(
        _hasAnyFilter ? 'Try adjusting your filters' : 'Tap Add User to get started',
        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
      ),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasAnyFilter ? _clearFilters : () => _showAddEditDialog(),
        icon: Icon(_hasAnyFilter ? Icons.filter_list_off : Icons.person_add),
        label: Text(_hasAnyFilter ? 'Clear Filters' : 'Add Team Member',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
            backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  // ===========================================================================
  //  SNACKBARS
  // ===========================================================================

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
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final FinanceBillingUser user;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({required this.user, required this.onTicketRaised, required this.onError});

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered  = [];
  Map<String, dynamic>?       _selectedEmp;
  bool   _loading   = true;
  bool   _assigning = false;
  String _priority  = 'Medium';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

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
      _filtered = q.isEmpty ? _employees : _employees.where((e) {
        return (e['name_parson'] ?? '').toLowerCase().contains(q) ||
               (e['email'] ?? '').toLowerCase().contains(q) ||
               (e['role'] ?? '').toLowerCase().contains(q);
      }).toList();
    });
  }

  String _buildTicketMessage() {
    final u = widget.user;
    return 'Team Member "${u.name}" (${u.email}) requires attention.\n\n'
           'Details:\n'
           '• Role   : ${u.role[0].toUpperCase()}${u.role.substring(1)}\n'
           '• Status : ${u.status.toUpperCase()}\n'
           '• Phone  : ${u.phone.isEmpty ? 'N/A' : u.phone}\n\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    'Team Member: ${widget.user.name}',
        message:    _buildTicketMessage(),
        priority:   _priority,
        timeline:   1440,
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
      widget.onError('Failed to assign ticket: $e');
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
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('User: ${widget.user.name}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
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
                child: Text(_buildTicketMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5)),
              ),
              const SizedBox(height: 20),

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
                      ? Container(height: 80, alignment: Alignment.center,
                          child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
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
                                      child: Text((emp['name_parson'] ?? 'U')[0].toUpperCase(),
                                          style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13)),
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
                                          child: Text(emp['role'].toString().toUpperCase(),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy)),
                                        ),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ]),
                                ),
                              );
                            },
                          )),
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
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _navy, foregroundColor: Colors.white,
                    disabledBackgroundColor: _navy.withOpacity(0.4),
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _assigning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee',
                        style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  ADD / EDIT USER DIALOG — original logic, unchanged
// =============================================================================
class _AddEditUserDialog extends StatefulWidget {
  final FinanceBillingUser? user;
  final String orgName;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const _AddEditUserDialog({this.user, required this.orgName, required this.onSave});

  @override
  State<_AddEditUserDialog> createState() => _AddEditUserDialogState();
}

class _AddEditUserDialogState extends State<_AddEditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _pwCtrl;
  String _role    = 'staff';
  bool   _saving  = false;
  bool   _obscure = true;

  final List<String> _roles = ['admin', 'accountant', 'staff'];

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.user?.name  ?? '');
    _emailCtrl = TextEditingController(text: widget.user?.email ?? '');
    _phoneCtrl = TextEditingController(text: widget.user?.phone ?? '');
    _pwCtrl    = TextEditingController();
    _role      = widget.user?.role ?? 'staff';
    if (!_roles.contains(_role)) _role = 'staff';
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _pwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.user != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: Icon(isEdit ? Icons.edit : Icons.person_add, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isEdit ? 'Edit User' : 'Add Team Member',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(widget.orgName, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(children: [
                _field(_nameCtrl, 'Full Name', Icons.person_outline,
                    validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 14),
                _field(_emailCtrl, 'Email', Icons.email_outlined,
                    readOnly: isEdit, keyType: TextInputType.emailAddress,
                    validator: (v) { if (v!.trim().isEmpty) return 'Required'; if (!v.contains('@')) return 'Invalid email'; return null; }),
                const SizedBox(height: 14),
                _field(_phoneCtrl, 'Phone', Icons.phone_outlined,
                    keyType: TextInputType.phone,
                    validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: _dec('Role', Icons.badge_outlined),
                  items: _roles.map((r) => DropdownMenuItem(
                      value: r, child: Text(r[0].toUpperCase() + r.substring(1)))).toList(),
                  onChanged: (v) => setState(() => _role = v!),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pwCtrl, obscureText: _obscure,
                  decoration: _dec(isEdit ? 'New password (leave blank to keep)' : 'Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.grey.shade500),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => !isEdit && (v == null || v.isEmpty) ? 'Password required' : null,
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2463AE), foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF2463AE).withOpacity(0.5),
                        elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(isEdit ? 'Update' : 'Add User', style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyType, bool readOnly = false, String? Function(String?)? validator}) {
    return TextFormField(
        controller: ctrl, keyboardType: keyType, readOnly: readOnly,
        decoration: _dec(label, icon), validator: validator);
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
    filled: true, fillColor: const Color(0xFFF7F9FC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2463AE), width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'name':  _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'role':  _role,
      if (_pwCtrl.text.isNotEmpty) 'password': _pwCtrl.text,
    };
    await widget.onSave(data);
    if (mounted) Navigator.pop(context);
    setState(() => _saving = false);
  }
}

// =============================================================================
//  USER DETAILS DIALOG — original logic, unchanged
// =============================================================================
class _UserDetailsDialog extends StatelessWidget {
  final FinanceBillingUser user;
  const _UserDetailsDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1A3A6B), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 28, backgroundColor: Colors.white24,
                child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                Text(user.role[0].toUpperCase() + user.role.substring(1),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              _row(Icons.email_outlined,  'Email',  user.email),
              _row(Icons.phone_outlined,  'Phone',  user.phone.isEmpty ? 'N/A' : user.phone),
              _row(Icons.info_outline,    'Status', user.status.toUpperCase()),
              _row(Icons.badge_outlined,  'Role',   user.role[0].toUpperCase() + user.role.substring(1)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(children: [
      Icon(icon, color: const Color(0xFF2463AE), size: 20),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF0D1B3E), fontWeight: FontWeight.w500)),
      ]),
    ]),
  );
}