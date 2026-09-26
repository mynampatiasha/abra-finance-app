import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// FIXED ASSETS LIST PAGE
// ============================================================================
// File: lib/screens/billing/pages/fixed_assets_list_page.dart
// ============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'new_fixed_asset.dart';
import '../../../../core/permissions_finance.dart';

// ─── Model ───────────────────────────────────────────────────────────────────

class FixedAsset {
  final String id;
  final String assetNumber;
  final String assetName;
  final String assetType;
  final String status;
  final double assetCost;
  final double currentValue;
  final double totalDepreciation;
  final String purchaseDate;
  final String depreciationMethod;
  final String? vendor;
  final String? serialNumber;
  final String? notes;

  FixedAsset({
    required this.id,
    required this.assetNumber,
    required this.assetName,
    required this.assetType,
    required this.status,
    required this.assetCost,
    required this.currentValue,
    required this.totalDepreciation,
    required this.purchaseDate,
    required this.depreciationMethod,
    this.vendor,
    this.serialNumber,
    this.notes,
  });

  factory FixedAsset.fromJson(Map<String, dynamic> j) => FixedAsset(
        id: j['_id'] ?? '',
        assetNumber: j['assetNumber'] ?? '',
        assetName: j['assetName'] ?? '',
        assetType: j['assetType'] ?? '',
        status: j['status'] ?? 'Draft',
        assetCost: (j['assetCost'] ?? 0).toDouble(),
        currentValue: (j['currentValue'] ?? 0).toDouble(),
        totalDepreciation: (j['totalDepreciation'] ?? 0).toDouble(),
        purchaseDate: j['purchaseDate'] ?? '',
        depreciationMethod: j['depreciationMethod'] ?? 'straight_line',
        vendor: j['vendor'],
        serialNumber: j['serialNumber'],
        notes: j['notes'],
      );

  double get depreciationPercent =>
      assetCost > 0 ? (totalDepreciation / assetCost) * 100 : 0;
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class FixedAssetsListPage extends StatefulWidget {
  final String baseUrl;
  final String token;
  const FixedAssetsListPage(
      {super.key, required this.baseUrl, required this.token});

  @override
  State<FixedAssetsListPage> createState() => _FixedAssetsListPageState();
}

class _FixedAssetsListPageState extends State<FixedAssetsListPage> {
  // ── State ─────────────────────────────────────────────────────────────────
  List<FixedAsset> _assets = [];
  List<FixedAsset> _filtered = [];
  bool _loading = true;
  String _selectedStatus = 'All';
  String _selectedType = 'All';
  final _searchCtrl = TextEditingController();

  // Stats
  double _totalCost = 0;
  double _totalCurrentVal = 0;
  double _totalDepreciated = 0;
  int _totalAssets = 0;

  static const _statusFilters = [
    'All',
    'Draft',
    'Active',
    'Fully Depreciated',
    'Disposed'
  ];
  static const _typeFilters = [
    'All',
    'IT Equipment',
    'Furniture & Fixtures',
    'Machinery',
    'Vehicle',
    'Building',
    'Land',
    'Office Equipment',
    'Other'
  ];

  // Status colour helper
  Color _statusColor(String s) => switch (s) {
        'Active' => const Color(0xFF2E7D32),
        'Draft' => const Color(0xFF1565C0),
        'Fully Depreciated' => const Color(0xFF6A1B9A),
        'Disposed' => const Color(0xFFBF360C),
        'Written Off' => const Color(0xFF37474F),
        _ => Colors.grey,
      };

  Color _statusBg(String s) => switch (s) {
        'Active' => const Color(0xFFE8F5E9),
        'Draft' => const Color(0xFFE3F2FD),
        'Fully Depreciated' => const Color(0xFFF3E5F5),
        'Disposed' => const Color(0xFFFBE9E7),
        'Written Off' => const Color(0xFFECEFF1),
        _ => const Color(0xFFF5F5F5),
      };

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilters);
    _loadAssets();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  Future<void> _loadAssets() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/finance/fixed-assets'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list =
            (data['data'] as List).map((e) => FixedAsset.fromJson(e)).toList();
        setState(() {
          _assets = list;
          _totalAssets = list.length;
          _totalCost = list.fold(0, (s, a) => s + a.assetCost);
          _totalCurrentVal = list.fold(0, (s, a) => s + a.currentValue);
          _totalDepreciated = list.fold(0, (s, a) => s + a.totalDepreciation);
        });
        _applyFilters();
      }
    } catch (e) {
      _showSnack('Error loading assets: $e', error: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _assets.where((a) {
        final matchSearch = q.isEmpty ||
            a.assetName.toLowerCase().contains(q) ||
            a.assetNumber.toLowerCase().contains(q) ||
            (a.vendor?.toLowerCase().contains(q) ?? false);
        final matchStatus =
            _selectedStatus == 'All' || a.status == _selectedStatus;
        final matchType =
            _selectedType == 'All' || a.assetType == _selectedType;
        return matchSearch && matchStatus && matchType;
      }).toList();
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _activateAsset(FixedAsset asset) async {
    try {
      final res = await http.patch(
        Uri.parse(
            '${widget.baseUrl}/api/finance/fixed-assets/${asset.id}/activate'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _showSnack('Asset activated successfully');
        _loadAssets();
      } else {
        _showSnack(data['message'] ?? 'Error activating asset', error: true);
      }
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _runDepreciation(FixedAsset asset) async {
    try {
      final res = await http.post(
        Uri.parse(
            '${widget.baseUrl}/api/finance/fixed-assets/${asset.id}/depreciate'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _showSnack('Depreciation posted: ₹${data['data']['amount']}');
        _loadAssets();
      } else {
        _showSnack(data['message'] ?? 'Error running depreciation',
            error: true);
      }
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _deleteAsset(FixedAsset asset) async {
    final canDelete = await FinancePermissions.checkCanDelete(context, 'assets');
    if (!canDelete) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Asset'),
        content: Text('Delete "${asset.assetName}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final res = await http.delete(
        Uri.parse('${widget.baseUrl}/api/finance/fixed-assets/${asset.id}'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _showSnack('Asset deleted');
        _loadAssets();
      } else {
        _showSnack(data['message'] ?? 'Error deleting asset', error: true);
      }
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _disposeAsset(FixedAsset asset) async {
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedReason = 'Disposed';

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Dispose / Write-off: ${asset.assetName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedReason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: ['Disposed', 'Written Off', 'Sold']
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => selectedReason = v ?? selectedReason,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sale Amount (₹)',
                hintText: '0 if write-off',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final res = await http.post(
                  Uri.parse(
                      '${widget.baseUrl}/api/finance/fixed-assets/${asset.id}/dispose'),
                  headers: _headers,
                  body: jsonEncode({
                    'disposalReason': selectedReason,
                    'disposalAmount': double.tryParse(amountCtrl.text) ?? 0,
                    'disposalDate':
                        DateTime.now().toIso8601String().split('T')[0],
                  }),
                );
                final data = jsonDecode(res.body);
                if (res.statusCode == 200) {
                  _showSnack('Asset $selectedReason successfully');
                  _loadAssets();
                } else {
                  _showSnack(data['message'] ?? 'Error', error: true);
                }
              } catch (e) {
                _showSnack('Error: $e', error: true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg, isError: true);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Fixed Assets',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAssets,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => NewFixedAssetPage(
                      baseUrl: widget.baseUrl,
                      token: widget.token,
                    )),
          );
          if (result == true) _loadAssets();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Asset'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStatsRow(),
                _buildFiltersBar(),
                Expanded(child: _buildAssetList()),
              ],
            ),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _statCard('Total Assets', '$_totalAssets', Icons.inventory_2_outlined,
              const Color(0xFF1565C0)),
          _statCard('Total Cost', '₹${_fmt(_totalCost)}', Icons.attach_money,
              const Color(0xFF2E7D32)),
          _statCard('Current Value', '₹${_fmt(_totalCurrentVal)}',
              Icons.trending_down, const Color(0xFF6A1B9A)),
          _statCard('Depreciated', '₹${_fmt(_totalDepreciated)}',
              Icons.money_off, const Color(0xFFBF360C)),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ── Filters ───────────────────────────────────────────────────────────────
  Widget _buildFiltersBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          // Search
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by name, number, vendor…',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: const Color(0xFFF7F8FA),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Status chips
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _statusFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final s = _statusFilters[i];
                final selected = s == _selectedStatus;
                return ChoiceChip(
                  label: Text(s,
                      style: TextStyle(
                          fontSize: 12,
                          color: selected ? Colors.white : Colors.black87)),
                  selected: selected,
                  selectedColor: const Color(0xFF1A1A2E),
                  backgroundColor: const Color(0xFFF0F0F0),
                  onSelected: (_) {
                    setState(() => _selectedStatus = s);
                    _applyFilters();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Type dropdown
          DropdownButtonFormField<String>(
            value: _selectedType,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'Filter by Type',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: _typeFilters
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) {
              setState(() => _selectedType = v ?? 'All');
              _applyFilters();
            },
          ),
        ],
      ),
    );
  }

  // ── Asset List ────────────────────────────────────────────────────────────
  Widget _buildAssetList() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No assets found',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _buildAssetCard(_filtered[i]),
    );
  }

  Widget _buildAssetCard(FixedAsset asset) {
    final depPct = asset.depreciationPercent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_assetTypeIcon(asset.assetType),
                      color: const Color(0xFF1A1A2E), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(asset.assetName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text('${asset.assetNumber} · ${asset.assetType}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      if (asset.vendor != null) ...[
                        const SizedBox(height: 2),
                        Text('Vendor: ${asset.vendor}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusBg(asset.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(asset.status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(asset.status))),
                ),
              ],
            ),
          ),

          // Amounts row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _amountCell('Purchase Cost', '₹${_fmt(asset.assetCost)}'),
                _amountCell('Current Value', '₹${_fmt(asset.currentValue)}',
                    color: const Color(0xFF2E7D32)),
                _amountCell('Depreciated', '₹${_fmt(asset.totalDepreciation)}',
                    color: const Color(0xFFBF360C)),
              ],
            ),
          ),

          // Depreciation progress bar
          if (asset.status != 'Draft') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Depreciation',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                      Text('${depPct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: depPct / 100,
                      backgroundColor: const Color(0xFFF0F0F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          depPct >= 90 ? Colors.red : const Color(0xFF1A1A2E)),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                if (asset.status == 'Draft') ...[
                  _actionBtn('Activate', Icons.play_arrow, Colors.green,
                      () => _activateAsset(asset)),
                  _actionBtn('Delete', Icons.delete_outline, Colors.red,
                      () => _deleteAsset(asset)),
                ],
                if (asset.status == 'Active') ...[
                  _actionBtn('Depreciate', Icons.trending_down,
                      const Color(0xFF6A1B9A), () => _runDepreciation(asset)),
                  _actionBtn('Dispose', Icons.remove_circle_outline,
                      Colors.orange, () => _disposeAsset(asset)),
                ],
                if (asset.status == 'Fully Depreciated') ...[
                  _actionBtn('Dispose', Icons.remove_circle_outline,
                      Colors.orange, () => _disposeAsset(asset)),
                ],
                const Spacer(),
                Text('Purchased: ${asset.purchaseDate}',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountCell(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color ?? const Color(0xFF1A1A2E))),
        ],
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8)),
    );
  }

  IconData _assetTypeIcon(String type) => switch (type) {
        'IT Equipment' => Icons.computer,
        'Furniture & Fixtures' => Icons.chair,
        'Machinery' => Icons.precision_manufacturing,
        'Vehicle' => Icons.directions_car,
        'Building' => Icons.business,
        'Land' => Icons.landscape,
        'Office Equipment' => Icons.print,
        _ => Icons.inventory_2,
      };

  String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}
