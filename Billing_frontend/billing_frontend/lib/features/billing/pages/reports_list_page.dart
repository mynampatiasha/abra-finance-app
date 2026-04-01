// ============================================================================
// REPORTS LIST PAGE - Zoho Books exact layout
// ============================================================================
// File: lib/screens/billing/pages/reports_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import '../../../../core/finance_secure_storage.dart';
import '../../../../core/services/reports_service.dart';
import '../app_top_bar.dart';
import 'report_viewer_page.dart';

const Color _navy   = Color(0xFF1e3a8a);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _purple = Color(0xFF9B59B6);
const Color _teal   = Color(0xFF1ABC9C);
const Color _red    = Color(0xFFE74C3C);
const Color _indigo = Color(0xFF6366F1);
const Color _pink   = Color(0xFFEC4899);
const Color _amber  = Color(0xFFF59E0B);
const Color _slate  = Color(0xFF64748B);

final Map<String, IconData> _categoryIcons = {
  'Business Overview':        Icons.bar_chart_rounded,
  'Sales':                    Icons.trending_up_rounded,
  'Receivables':              Icons.account_balance_wallet_outlined,
  'Payments Received':        Icons.payments_rounded,
  'Recurring Invoices':       Icons.repeat_rounded,
  'Payables':                 Icons.receipt_outlined,
  'Purchases and Expenses':   Icons.shopping_cart_outlined,
  'Taxes':                    Icons.receipt_long_outlined,
  'Banking':                  Icons.account_balance_outlined,
  'Accountant':               Icons.calculate_outlined,
  'Activity':                 Icons.history_rounded,
};

final Map<String, Color> _categoryColors = {
  'Business Overview':        _navy,
  'Sales':                    _green,
  'Receivables':              _blue,
  'Payments Received':        _teal,
  'Recurring Invoices':       _indigo,
  'Payables':                 _orange,
  'Purchases and Expenses':   _purple,
  'Taxes':                    _red,
  'Banking':                  _slate,
  'Accountant':               _amber,
  'Activity':                 _pink,
};

// ─────────────────────────────────────────────────────────────────────────────

class ReportsListPage extends StatefulWidget {
  const ReportsListPage({Key? key}) : super(key: key);

  @override
  State<ReportsListPage> createState() => _ReportsListPageState();
}

class _ReportsListPageState extends State<ReportsListPage> {
  List<ReportCategory> _categories = [];
  bool    _isLoading   = true;
  String? _error;
  String  _selected    = '';
  String  _search      = '';
  String  _orgName     = '';

  final _searchCtrl  = TextEditingController();
  final _sideScroll  = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _loadOrg();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sideScroll.dispose();
    super.dispose();
  }

  Future<void> _loadOrg() async {
    final n = await FinanceSecureStorage.getOrgName() ?? '';
    if (mounted) setState(() => _orgName = n);
  }

  Future<void> _loadMeta() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final cats = await ReportsService.getMeta();
      setState(() {
        _categories = cats;
        _isLoading  = false;
        _selected   = cats.isNotEmpty ? cats.first.category : '';
      });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  // ── Filtered categories / reports ─────────────────────────────────────────
  List<ReportCategory> get _filtered {
    if (_search.isEmpty) return _categories;
    return _categories.map((cat) {
      final reps = cat.reports.where((r) => r.name.toLowerCase().contains(_search)).toList();
      return reps.isEmpty ? null : ReportCategory(category: cat.category, reports: reps);
    }).whereType<ReportCategory>().toList();
  }

  List<ReportMeta> get _currentReports {
    if (_search.isNotEmpty) return _filtered.expand((c) => c.reports).toList();
    final match = _categories.where((c) => c.category == _selected);
    return match.isNotEmpty ? match.first.reports : [];
  }

  int get _total => _categories.fold(0, (s, c) => s + c.reports.length);

  void _open(ReportMeta r) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => ReportViewerPage(report: r, orgName: _orgName)));

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Reports'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : _error != null ? _buildError()
          : Column(children: [
              _buildTopBar(),
              Expanded(child: LayoutBuilder(
                builder: (_, c) => c.maxWidth >= 800
                    ? _buildDesktop()
                    : _buildMobile(),
              )),
            ]),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(children: [
        // Search
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search reports…',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, size: 17, color: Colors.grey[400]),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 15), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                    : null,
                filled: true, fillColor: const Color(0xFFF7F9FC),
                isDense: true, contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(onTap: _loadMeta, borderRadius: BorderRadius.circular(8),
          child: Container(width: 40, height: 40,
            decoration: BoxDecoration(color: const Color(0xFFF1F1F1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
            child: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF7F8C8D)))),
        const SizedBox(width: 16),
        if (_orgName.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _navy.withOpacity(0.07), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.business, size: 13, color: _navy),
              const SizedBox(width: 5),
              Text(_orgName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
            ]),
          ),
          const SizedBox(width: 12),
        ],
        Text('$_total Reports', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ── Desktop: sidebar + content ────────────────────────────────────────────
  Widget _buildDesktop() {
    return Row(children: [
      // LEFT SIDEBAR
      Container(
        width: 230,
        color: Colors.white,
        child: Column(children: [
          // "All Reports" header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              const Icon(Icons.grid_view_rounded, size: 15, color: _navy),
              const SizedBox(width: 6),
              Text('Report Category', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[500], letterSpacing: 0.5)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _sideScroll,
              child: ListView(
                controller: _sideScroll,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: _categories.map((cat) => _sidebarItem(cat)).toList(),
              ),
            ),
          ),
          // Bottom total
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 14, color: _navy),
              const SizedBox(width: 6),
              Text('$_total Total Reports', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
      const VerticalDivider(width: 1, color: Color(0xFFE8EEF4)),
      // RIGHT CONTENT
      Expanded(child: _buildContent()),
    ]);
  }

  Widget _sidebarItem(ReportCategory cat) {
    final color   = _categoryColors[cat.category] ?? _navy;
    final icon    = _categoryIcons[cat.category]  ?? Icons.description_outlined;
    final isActive = _selected == cat.category && _search.isEmpty;

    return InkWell(
      onTap: () { _searchCtrl.clear(); setState(() { _selected = cat.category; _search = ''; }); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.09) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: isActive ? color.withOpacity(0.35) : Colors.transparent),
        ),
        child: Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(color: isActive ? color : color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: 15, color: isActive ? Colors.white : color)),
          const SizedBox(width: 10),
          Expanded(child: Text(cat.category,
            style: TextStyle(fontSize: 12.5, fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive ? color : const Color(0xFF374151)),
            maxLines: 2)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isActive ? color.withOpacity(0.15) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10)),
            child: Text('${cat.reports.length}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: isActive ? color : Colors.grey[500]))),
        ]),
      ),
    );
  }

  // ── Mobile: stacked ───────────────────────────────────────────────────────
  Widget _buildMobile() {
    return Column(children: [
      // Category horizontal scroll
      Container(
        height: 44, color: Colors.white,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: _categories.map((cat) {
            final color   = _categoryColors[cat.category] ?? _navy;
            final isActive = _selected == cat.category && _search.isEmpty;
            return GestureDetector(
              onTap: () { _searchCtrl.clear(); setState(() { _selected = cat.category; _search = ''; }); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? color : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isActive ? color : const Color(0xFFDDE3EE))),
                child: Text(cat.category,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : Colors.grey[600])),
              ),
            );
          }).toList(),
        ),
      ),
      const Divider(height: 1),
      Expanded(child: _buildContent()),
    ]);
  }

  // ── Content area (right panel) ────────────────────────────────────────────
  Widget _buildContent() {
    final reports = _currentReports;

    if (reports.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(_search.isNotEmpty ? 'No reports match "$_search"' : 'No reports found',
            style: TextStyle(fontSize: 15, color: Colors.grey[500])),
      ]));
    }

    if (_search.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 10),
              child: Text('${reports.length} results for "$_search"',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          ...reports.map((r) => _reportTile(r, showCat: true)),
        ],
      );
    }

    final catColor = _categoryColors[_selected] ?? _navy;
    final catIcon  = _categoryIcons[_selected]  ?? Icons.description_outlined;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Category header
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: catColor.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: catColor.withOpacity(0.18))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: catColor, borderRadius: BorderRadius.circular(7)),
              child: Icon(catIcon, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_selected, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: catColor)),
              Text('${reports.length} reports available',
                  style: TextStyle(fontSize: 11, color: catColor.withOpacity(0.7))),
            ])),
          ]),
        ),
        // Reports list
        ...reports.map((r) => _reportTile(r)),
      ],
    );
  }

  Widget _reportTile(ReportMeta r, {bool showCat = false}) {
    final cat      = _getCatFor(r);
    final catColor = _categoryColors[cat] ?? _navy;
    final catIcon  = _categoryIcons[cat]  ?? Icons.description_outlined;

    return InkWell(
      onTap: () => _open(r),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE8EEF4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))]),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: catColor.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
            child: Icon(catIcon, size: 18, color: catColor)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1A202C))),
            if (showCat) Text(cat, style: TextStyle(fontSize: 11, color: catColor, fontWeight: FontWeight.w500)),
          ])),
          const Icon(Icons.chevron_right, size: 17, color: Color(0xFFCBD5E1)),
        ]),
      ),
    );
  }

  String _getCatFor(ReportMeta r) {
    for (final c in _categories) {
      if (c.reports.any((x) => x.key == r.key)) return c.category;
    }
    return '';
  }

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 52, color: Colors.red[400]),
    const SizedBox(height: 12),
    Text('Failed to load reports', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
    const SizedBox(height: 8),
    Text(_error ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500]), textAlign: TextAlign.center),
    const SizedBox(height: 20),
    ElevatedButton.icon(onPressed: _loadMeta, icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
  ]));
}