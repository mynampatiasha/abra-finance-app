import 'package:abra_finance/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import 'package:excel/excel.dart' as xlsLib;
import '../../../../core/services/invoice_service.dart';
import '../../../../core/services/invoice_automation_service.dart';
import '../../../../core/finance_secure_storage.dart';
import '../app_top_bar.dart';
import 'new_invoice_automation.dart';

const List<String> kReportTypes = [
  'Customer Orders',
  'Fulfillment',
  'Inscan',
  'Outscan',
  'Delivered',
  'RTS',
  'RTO',
  'Cancelled Shipments',
  'Process for RTO',
  'RTO Inscan',
  'RTO Outscan',
  'RTO Delivered',
  'Undelivered Shipments',
  'Inventory',
  'Storage',
  'Products',
];

class InvoiceAutomationListPage extends StatefulWidget {
  const InvoiceAutomationListPage({Key? key}) : super(key: key);
  @override
  State<InvoiceAutomationListPage> createState() =>
      _InvoiceAutomationListPageState();
}

class _InvoiceAutomationListPageState extends State<InvoiceAutomationListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Config state ────────────────────────────────────────────────────────
  String? _selectedReportType;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  // 0 = config only  1 = show filtered list
  int _step = 0;

  // ── Billed Shipments Filters ─────────────────────────────────────────────
  String? _billedSelectedReportType;
  DateTime _billedStartDate =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _billedEndDate =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  // ── Staging Drafts Filters ───────────────────────────────────────────────
  String _filterDraftsText = '';
  DateTime _stagingStartDate =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _stagingEndDate =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  // ── Summaries ────────────────────────────────────────────────────────────
  int _summaryStagingCount = 0;
  int _summaryBilledCount = 0;

  // ── Data ────────────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _error;
  List<dynamic> _rawData = [];
  List<Invoice> _drafts = [];
  int _draftCount = 0;
  List<dynamic> _billedShipments = [];
  bool _isLoadingBilled = false;
  int _billedCountForCurrentFilter = 0;
  String _billedFilterSender = '';

  // ── Filters & Selection ──────────────────────────────────────────────────
  String _filterSenderName = '';
  String _filterCustomerName = '';
  String _filterShippingMethod = '';
  String _filterRemarks = '';
  String _filterTrackingNo = '';
  String _filterBilledText = '';
  String _filterGlobal = '';

  final _senderController = TextEditingController();
  final _customerController = TextEditingController();
  final _shippingController = TextEditingController();
  final _remarksController = TextEditingController();
  final _trackingController = TextEditingController();
  final _globalController = TextEditingController();
  final _draftsSearchController = TextEditingController();
  final _billedSearchController = TextEditingController();

  int _visibleCount = 20;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _tableScrollController = ScrollController();
  final ScrollController _headerScrollController = ScrollController();
  Set<String> _selectedShipmentKeys = {};

  Timer? _debounce;
  Timer? _debounceCustomer;
  Timer? _debounceShipping;
  Timer? _debounceRemarks;
  Timer? _debounceTracking;
  Timer? _debounceGlobal;
  Timer? _debounceDrafts;
  Timer? _debounceBilled;
  String _currentRole = '';
  bool get _isApprover =>
      _currentRole == 'owner' || _currentRole == 'admin';

  // Previous-calendar-month pending status (Feature: month gating).
  Map<String, dynamic>? _prevMonthStatus;
  bool get _prevMonthBlocked => _prevMonthStatus?['blocked'] == true;

  @override
  void initState() {
    super.initState();
    _initRole();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == 1) {
        _fetchDrafts();
      }
      if (!_tabController.indexIsChanging && _tabController.index == 2) {
        _fetchBilledShipments();
      }
    });
    _tableScrollController.addListener(() {
      if (_tableScrollController.position.pixels >=
          _tableScrollController.position.maxScrollExtent - 100) {
        if (_visibleCount < _rawData.length) {
          // filteredData equivalent
          setState(() =>
              _visibleCount = (_visibleCount + 20).clamp(0, _rawData.length));
        }
      }
    });
  }

  Future<void> _initRole() async {
    final role = await FinanceSecureStorage.getRole();
    if (mounted) setState(() => _currentRole = role ?? '');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
    _debounceCustomer?.cancel();
    _debounceShipping?.cancel();
    _debounceRemarks?.cancel();
    _debounceTracking?.cancel();
    _debounceGlobal?.cancel();
    _debounceDrafts?.cancel();
    _debounceBilled?.cancel();
    _senderController.dispose();
    _customerController.dispose();
    _shippingController.dispose();
    _remarksController.dispose();
    _trackingController.dispose();
    _globalController.dispose();
    _draftsSearchController.dispose();
    _billedSearchController.dispose();
    _horizontalScrollController.dispose();
    _headerScrollController.dispose();
    _tableScrollController.dispose();
    super.dispose();
  }

  // ── API calls ────────────────────────────────────────────────────────────
  Future<void> _generateReport() async {
    if (_selectedReportType == null) {
      AppSnackbar.show(context, message: 'Please select a Report Type first');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedShipmentKeys.clear();
    });
    try {
      final data = await InvoiceAutomationService.getUnbilledShipments(
        reportType: _selectedReportType!,
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate),
      );
      if (data['success'] == true) {
        final shipments = data['shipments'] as List<dynamic>? ?? [];

        // The summary staging count should just be the number of shipments hidden in staging
        final stagingCount = data['draftCount'] ?? 0;

        // Fetch summary counts for the billed shipments for this exact date range and report type
        final billedData = await InvoiceAutomationService.getBilledShipments(
          startDate: DateFormat('yyyy-MM-dd').format(_startDate),
          endDate: DateFormat('yyyy-MM-dd').format(_endDate),
          reportType: _selectedReportType,
        );
        final billedCount =
            (billedData['shipments'] as List<dynamic>? ?? []).length;

        setState(() {
          _rawData = shipments;
          _visibleCount = 20;
          _draftCount = data['draftCount'] ?? 0;
          _summaryStagingCount = stagingCount;
          _summaryBilledCount = billedCount;
          _isLoading = false;
        });

        // Also fetch default drafts and billed shipments for their respective tabs
        _fetchBilledShipments();
        _fetchDrafts();
        _fetchPrevMonthStatus();
      } else {
        setState(() {
          _error = data['message'] ?? 'Failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Month gating ────────────────────────────────────────────────────────
  Future<void> _fetchPrevMonthStatus() async {
    try {
      final data = await InvoiceAutomationService.getPrevMonthStatus(
          DateFormat('yyyy-MM-dd').format(_startDate));
      if (mounted) setState(() => _prevMonthStatus = data);
    } catch (_) {
      // non-fatal — leave the gate un-evaluated rather than block on an error
      if (mounted) setState(() => _prevMonthStatus = null);
    }
  }

  Future<void> _grantOverride() async {
    final s = _prevMonthStatus;
    if (s == null) return;
    final month = s['month']?.toString() ?? '';
    final label = s['monthLabel']?.toString() ?? month;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Override — unlock $label'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '$label still has ${s['totalPending']} pending shipment(s) '
            '(${s['pendingInStaging']} in Staging, ${s['pendingInProcessing']} in Processing). '
            'Granting this override lets the finance team generate invoices for the '
            'next month anyway. This is logged against your account.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Grant override')),
        ],
      ),
    );
    if (ok != true) return;
    if (reasonCtrl.text.trim().isEmpty) {
      AppSnackbar.show(context,
          message: 'A reason is required to grant an override.', isError: true);
      return;
    }
    try {
      await InvoiceAutomationService.createMonthOverride(
          month, reasonCtrl.text.trim());
      AppSnackbar.show(context, message: 'Override granted for $label.');
      await _fetchPrevMonthStatus();
    } catch (e) {
      AppSnackbar.show(context,
          message: 'Failed to grant override: $e', isError: true);
    }
  }

  Future<void> _showOverrideHistory() async {
    List<Map<String, dynamic>> rows = [];
    try {
      rows = await InvoiceAutomationService.getMonthOverrides();
    } catch (e) {
      AppSnackbar.show(context, message: 'Failed to load history: $e', isError: true);
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Override history'),
        content: SizedBox(
          width: 560,
          child: rows.isEmpty
              ? const Text('No overrides granted yet.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: rows.map((r) {
                      final at = r['createdAt']?.toString() ?? '';
                      return ListTile(
                        dense: true,
                        title: Text(
                            'Month ${r['month']}  ·  ${r['approvedByEmail'] ?? ''} (${r['approvedByRole'] ?? ''})'
                            '${r['revoked'] == true ? '  ·  REVOKED' : ''}'),
                        subtitle: Text('${r['reason'] ?? ''}\n$at'),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _fetchBilledShipments() async {
    setState(() => _isLoadingBilled = true);
    try {
      final data = await InvoiceAutomationService.getBilledShipments(
        reportType: _billedSelectedReportType,
        startDate: DateFormat('yyyy-MM-dd').format(_billedStartDate),
        endDate: DateFormat('yyyy-MM-dd').format(_billedEndDate),
      );
      if (data['success'] == true) {
        setState(() {
          _billedShipments = data['shipments'] as List<dynamic>? ?? [];
          _isLoadingBilled = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingBilled = false);
    }
  }

  Future<void> _fetchDrafts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final d = await InvoiceAutomationService.getAutomationDrafts();

      final start = DateTime(_stagingStartDate.year, _stagingStartDate.month,
          _stagingStartDate.day);
      final end = DateTime(_stagingEndDate.year, _stagingEndDate.month,
          _stagingEndDate.day, 23, 59, 59);

      bool inRange(DateTime dt) =>
          dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
          dt.isBefore(end.add(const Duration(seconds: 1)));

      // A draft can bundle shipments from many different dates, so its own
      // single invoiceDate isn't reliable for filtering — match by each
      // shipment item's own date (embedded as "Date: YYYY-MM-DD" in
      // itemDetails) instead, same as the Shipment Processing summary count.
      final dateLineRegex = RegExp(r'Date:\s*(\d{4}-\d{2}-\d{2})');

      final filtered = d.where((inv) {
        final itemDates = inv.items
            .map((item) => dateLineRegex.firstMatch(item.itemDetails))
            .whereType<RegExpMatch>()
            .map((m) => DateTime.tryParse(m.group(1)!))
            .whereType<DateTime>()
            .toList();

        if (itemDates.isNotEmpty) {
          return itemDates.any(inRange);
        }
        // Fallback for drafts with no parseable shipment dates (e.g. manual drafts)
        return inRange(inv.invoiceDate);
      }).toList();

      setState(() {
        _drafts = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Filtering Logic ──────────────────────────────────────────────────────
  List<dynamic> get _filteredData {
    return _rawData.where((s) {
      if (_filterGlobal.isNotEmpty) {
        final query = _filterGlobal.toLowerCase().trim();
        bool anyMatch = false;
        for (var val in s.values) {
          if (val != null && val.toString().toLowerCase().contains(query)) {
            anyMatch = true;
            break;
          }
        }
        if (!anyMatch) return false;
      }
      if (_filterTrackingNo.isNotEmpty) {
        final query = _filterTrackingNo
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        final tracking = _getShipmentKey(s)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (!tracking.contains(query)) return false;
      }
      if (_filterSenderName.isNotEmpty) {
        final query = _filterSenderName
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        final sender = (s['sender_name'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (!sender.contains(query)) return false;
      }
      if (_filterCustomerName.isNotEmpty) {
        final query = _filterCustomerName
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        final customer = (s['customer_name'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (!customer.contains(query)) return false;
      }
      if (_filterShippingMethod.isNotEmpty) {
        final query = _filterShippingMethod
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        final method = (s['shipping_method'] ?? s['service_type'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (!method.contains(query)) return false;
      }
      if (_filterRemarks.isNotEmpty) {
        final query =
            _filterRemarks.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final rem = (s['remarks'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (!rem.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  List<Invoice> get _filteredDrafts {
    if (_filterDraftsText.isEmpty) return _drafts;
    final query =
        _filterDraftsText.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _drafts.where((d) {
      final customer =
          (d.customerName).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final inv = (d.invoiceNumber ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      bool hasAL = false;
      for (var item in d.items) {
        final tracking = (item.unbilledShipmentTrackingNumber ?? '')
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        final details = (item.itemDetails)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (tracking.contains(query) || details.contains(query)) {
          hasAL = true;
          break;
        }
      }
      return customer.contains(query) || inv.contains(query) || hasAL;
    }).toList();
  }

  List<dynamic> get _filteredBilledShipments {
    if (_filterBilledText.isEmpty) return _billedShipments;
    final query =
        _filterBilledText.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _billedShipments.where((s) {
      final al = (s['tracking_no'] ?? s['id'] ?? '')
          .toString()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final sender = (s['sender_name'] ?? '')
          .toString()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final inv = (s['invoice_no'] ?? '')
          .toString()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      return al.contains(query) ||
          sender.contains(query) ||
          inv.contains(query);
    }).toList();
  }

  String _getShipmentKey(dynamic s) =>
      s['tracking_no']?.toString() ?? s['id']?.toString() ?? '';

  // ── Invoice Generation ───────────────────────────────────────────────────
  Future<void> _generateInvoiceFromSelection() async {
    final selectedItems = _rawData
        .where((s) => _selectedShipmentKeys.contains(_getShipmentKey(s)))
        .toList();

    if (selectedItems.isEmpty) return;

    // Month gate — the previous calendar month must be cleared (or overridden)
    // before this month's automation invoices can be generated.
    if (_prevMonthBlocked) {
      final label = _prevMonthStatus?['monthLabel'] ?? 'the previous month';
      AppSnackbar.show(
        context,
        message:
            'You are not allowed to generate invoices through automation — '
            '$label still has ${_prevMonthStatus?['totalPending']} pending shipment(s). '
            'Contact your management for approval.',
        isError: true,
      );
      return;
    }

    final invoiceItems = selectedItems.map<InvoiceItem>((s) {
      final subtotalShipping =
          double.tryParse(s['subtotal']?.toString() ?? '0') ?? 0.0;
      // Backend now sends chargeable_weight = max(actual weight, volumetric
      // weight) directly (see /unbilled-shipments) — use it. The manual
      // max() here is only a fallback for a response that predates that
      // backend change, not the primary path.
      final actualWeight = double.tryParse(s['weight']?.toString() ?? '0') ?? 0.0;
      final rawVolumetricWeight =
          double.tryParse(s['volumetric_weight']?.toString() ?? '0') ?? 0.0;
      final volumetricWeight = double.tryParse(
              s['chargeable_weight']?.toString() ?? '') ??
          (actualWeight > rawVolumetricWeight ? actualWeight : rawVolumetricWeight);

      // Detect Full Load by checking shipping_method or remarks (case-insensitive)
      final shippingMethod = (s['shipping_method'] ?? s['shipment_type'] ?? '')
          .toString()
          .toLowerCase();
      final remarks = (s['remarks'] ?? '').toString().toLowerCase();
      final isFullLoad = shippingMethod.contains('full load') ||
          shippingMethod.contains('full truck load') ||
          shippingMethod.contains('ftl') ||
          remarks.contains('full load') ||
          remarks.contains('full truck load') ||
          remarks.contains('ftl');

      double qty;
      double rate;
      // Direct mapping without intelligent guessing to strictly follow user rules
      String unit =
          (s['shipment_type'] ?? s['uom'] ?? s['unit'] ?? '').toString().trim();
      if (unit.isEmpty) unit = 'Nos';

      // Ensure the unit is properly capitalized if it matches known units
      if (unit.length > 1) {
        unit = unit[0].toUpperCase() + unit.substring(1).toLowerCase();
      }

      if (isFullLoad) {
        qty = 1.0; // Forcefully set to 1 for Full Load, regardless of DB value
      } else {
        qty = volumetricWeight > 0
            ? volumetricWeight
            : (double.tryParse(s['quantity']?.toString() ?? '1') ?? 1.0);
        if (qty <= 0) qty = 1.0;
        if (unit.toLowerCase() == 'nos' || unit.toLowerCase() == 'box')
          unit = 'Kg';
      }

      rate = 0;
      if (qty > 0) {
        rate = subtotalShipping / qty;
      }

      final tax = (qty * rate) * 0.18;
      final tracking = _getShipmentKey(s);
      final originCity = s['pickup_city']?.toString() ?? '';
      final destCity = s['destination_city']?.toString() ?? '';
      final locationString = (originCity.isNotEmpty || destCity.isNotEmpty)
          ? '$originCity - $destCity'
          : '${s['origin'] ?? ''} --TO-- ${s['destination'] ?? ''}'; // Fallback if cities are empty
      final date = (s['delivery_date']?.toString() ?? '').split(' ').first;

      String details =
          '$tracking\n$locationString\nDate: $date\nType: ${shippingMethod.toUpperCase()}';

      return InvoiceItem(
        itemDetails: details,
        hsnCode: '009965',
        unit: unit,
        quantity: qty,
        rate: rate,
        amount: (qty * rate) + tax,
        itemGstRate: 18,
        taxableAmount: (qty * rate),
        cgstAmount: tax / 2,
        sgstAmount: tax / 2,
        unbilledShipmentTrackingNumber: tracking,
      );
    }).toList();

    final firstItem = selectedItems.first;
    final customerName =
        (firstItem['customer_name'] ?? firstItem['sender_name'] ?? 'Unknown')
            .toString()
            .toUpperCase();

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewInvoiceAutomationScreen(
            initialItems: invoiceItems,
            initialCustomerName: customerName,
            pivotGroupName: 'BATCH INVOICE', // Generic group name
          ),
        ));

    // If draft was saved/approved, refresh to exclude those shipments
    if (result == true) _generateReport();
  }

  // ── Draft Actions ────────────────────────────────────────────────────────
  Future<void> _approveDraft(String id,
      {String? draftName, int? lineItemCount, double? totalAmount}) async {
    // ── Confirm before approving ──
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
          SizedBox(width: 8),
          Text('Approve to Finance?'),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (draftName != null)
                Text('Invoice for: $draftName',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              if (lineItemCount != null)
                Text('$lineItemCount shipment(s) will be marked as billed.',
                    style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200)),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'This action cannot be undone. The invoice will be pushed to Finance.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.orange))),
                ]),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_circle, size: 16),
            label: const Text('Yes, Approve'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    if (ok != true) return;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await InvoiceAutomationService.approveAutomationDraft(id);
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.show(context, message: 'Approved and pushed to Finance!');
        _fetchDrafts();
        _generateReport(); // refresh unbilled list too
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.show(context, message: 'Error: $e', isError: true);
      }
    }
  }

  Future<void> _revertBilledShipment(
      String trackingNo, String invoiceNo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: Colors.red, size: 24),
          SizedBox(width: 8),
          Text('Remove Billed Shipment?'),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tracking No: $trackingNo',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text('CRITICAL WARNING',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red))),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                          'This shipment is linked to Finance Invoice $invoiceNo.',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.red)),
                      const SizedBox(height: 4),
                      const Text(
                          'Removing this record will allow the shipment to be re-billed. However, the Finance Invoice will NOT be automatically cancelled.',
                          style: TextStyle(fontSize: 12, color: Colors.red)),
                      const SizedBox(height: 4),
                      const Text(
                          'You MUST manually cancel/void the invoice in the Finance module to avoid double billing.',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red)),
                    ]),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('I Understand, Remove'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    if (ok != true) return;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await InvoiceAutomationService.deleteBilledShipment(trackingNo);
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.show(context, message: 'Billed shipment tracking removed.');
        _fetchBilledShipments();
        _generateReport(); // Refresh unbilled list to show it again
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.show(context, message: 'Error: $e', isError: true);
      }
    }
  }

  Future<void> _revertDraft(String id) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await InvoiceAutomationService.deleteAutomationDraft(id);
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.show(context,
            message: 'Draft deleted. Shipments reverted to unbilled list.');
        _fetchDrafts();
        // If we also want to immediately refresh the main report:
        // _generateReport();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.show(context, message: 'Error: $e', isError: true);
      }
    }
  }

  // ── Date picker ──────────────────────────────────────────────────────────
  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  // ── Excel export ─────────────────────────────────────────────────────────
  void _exportToExcel() {
    final dataToExport = _filteredData;
    if (dataToExport.isEmpty) return;

    final cols =
        dataToExport.first.keys.where((k) => k != 'source_table').toList();
    final sheetName = (_selectedReportType ?? 'Report').replaceAll(' ', '_');
    final excel = xlsLib.Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel[sheetName];

    // Header row
    sheet.appendRow(cols
        .map((c) => xlsLib.TextCellValue(c.replaceAll('_', ' ').toUpperCase()))
        .toList());

    // Data rows
    for (final row in dataToExport) {
      sheet.appendRow(cols
          .map((c) => xlsLib.TextCellValue(row[c]?.toString() ?? ''))
          .toList());
    }

    excel.setDefaultSheet(sheetName);
    final bytes = excel.encode()!;
    final blob = html.Blob([bytes],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download',
          '${sheetName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
    AppSnackbar.show(context, message: 'Excel downloaded!');
  }

  void _exportDraftsToExcel() {
    if (_filteredDrafts.isEmpty) {
      AppSnackbar.show(context, message: 'No staging drafts to export.');
      return;
    }

    final excel = xlsLib.Excel.createExcel();
    final sheet = excel['Staging Drafts'];

    sheet.appendRow([
      xlsLib.TextCellValue('INVOICE NO'),
      xlsLib.TextCellValue('CUSTOMER NAME'),
      xlsLib.TextCellValue('LINE ITEMS'),
      xlsLib.TextCellValue('TOTAL AMOUNT (INR)'),
      xlsLib.TextCellValue('INVOICE DATE'),
      xlsLib.TextCellValue('STATUS'),
    ]);

    for (var d in _filteredDrafts) {
      sheet.appendRow([
        xlsLib.TextCellValue(d.invoiceNumber ?? ''),
        xlsLib.TextCellValue(d.customerName),
        xlsLib.TextCellValue(d.items.length.toString()),
        xlsLib.TextCellValue(d.totalAmount.toStringAsFixed(2)),
        xlsLib.TextCellValue(DateFormat('yyyy-MM-dd').format(d.invoiceDate)),
        xlsLib.TextCellValue('Staging Draft'),
      ]);
    }

    final bytes = excel.encode()!;
    final blob = html.Blob([bytes],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download',
          'Staging_Drafts_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
    AppSnackbar.show(context, message: 'Staging Drafts Excel downloaded!');
  }

  // =========================================================================
  // BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Invoice Automation'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(children: [
        TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.indigo,
          indicatorWeight: 3,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(text: 'Shipment Processing'),
            Tab(text: 'Staging Drafts'),
            Tab(text: 'Billed Shipments'),
          ],
        ),
        Expanded(
            child: TabBarView(controller: _tabController, children: [
          _buildReportTab(),
          _buildDraftsTab(),
          _buildBilledShipmentsTab(),
        ])),
      ]),
    );
  }

  // =========================================================================
  // TAB 1 — Shipment Processing
  // =========================================================================
  Widget _buildReportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildConfigCard(),
        if (_isLoading) ...[
          const SizedBox(height: 40),
          const Center(child: CircularProgressIndicator()),
        ] else if (_error != null) ...[
          const SizedBox(height: 24),
          Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red))),
        ] else if (_rawData.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildFilteredListCard(),
        ],
      ]),
    );
  }

  // ── Config card ──────────────────────────────────────────────────────────
  Widget _buildConfigCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.settings, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text('Report Configuration',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const Divider(height: 24),
              Row(children: [
                Expanded(
                    flex: 3,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('REPORT TYPE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8)),
                            child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                              value: _selectedReportType,
                              hint: const Text('-- Select Report Type --',
                                  style: TextStyle(color: Colors.grey)),
                              isExpanded: true,
                              items: kReportTypes
                                  .map((t) => DropdownMenuItem(
                                      value: t, child: Text(t)))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _selectedReportType = v;
                              }),
                            )),
                          ),
                        ])),
                const SizedBox(width: 16),
                Expanded(
                    flex: 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('START DATE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1)),
                          const SizedBox(height: 6),
                          SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _pickStartDate,
                                icon: const Icon(Icons.calendar_today,
                                    size: 16, color: Colors.indigo),
                                label: Text(
                                    DateFormat('dd/MM/yyyy').format(_startDate),
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.black87)),
                                style: OutlinedButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 14),
                                    side: BorderSide(color: Colors.grey[300]!),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8))),
                              )),
                        ])),
                const SizedBox(width: 16),
                Expanded(
                    flex: 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('END DATE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1)),
                          const SizedBox(height: 6),
                          SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _pickEndDate,
                                icon: const Icon(Icons.calendar_today,
                                    size: 16, color: Colors.indigo),
                                label: Text(
                                    DateFormat('dd/MM/yyyy').format(_endDate),
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.black87)),
                                style: OutlinedButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 14),
                                    side: BorderSide(color: Colors.grey[300]!),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8))),
                              )),
                        ])),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _generateReport,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.cloud_download),
                    label: Text(
                        _isLoading ? 'Fetching Data...' : 'PULL SHIPMENTS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
            ],
          )),
    );
  }

  // ── Filtered List & Selection ────────────────────────────────────────────
  Widget _buildFilteredListCard() {
    final filtered = _filteredData;
    final cols = filtered.isNotEmpty
        ? filtered.first.keys.where((k) => k != 'source_table').toList()
        : <String>[];

    // Check if ALL filtered items are selected
    bool allSelected = false;
    if (filtered.isNotEmpty) {
      allSelected = filtered
          .every((s) => _selectedShipmentKeys.contains(_getShipmentKey(s)));
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── FILTER BAR ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    // Global / Universal Search Row
                    Row(children: [
                      const Icon(Icons.search, color: Colors.indigo),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Focus(
                              onKeyEvent: (node, event) =>
                                  KeyEventResult.skipRemainingHandlers,
                              child: TextField(
                                controller: _globalController,
                                decoration: InputDecoration(
                                  hintText:
                                      'Company Name / Universal Search (searches all fields like Sender, Receiver, Email, etc.)...',
                                  prefixIcon: const Icon(Icons.travel_explore,
                                      size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                          color: Colors.indigo[300]!,
                                          width: 2)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                          color: Colors.indigo[300]!,
                                          width: 2)),
                                ),
                                onChanged: (v) {
                                  if (_debounceGlobal?.isActive ?? false)
                                    _debounceGlobal!.cancel();
                                  _debounceGlobal = Timer(
                                      const Duration(milliseconds: 500), () {
                                    setState(() => _filterGlobal = v);
                                  });
                                },
                              ))),
                    ]),
                    const SizedBox(height: 10),
                    // Original Column Filters Row
                    Row(children: [
                      const Icon(Icons.filter_list, color: Colors.indigo),
                      const SizedBox(width: 12),
                      // Smart AL Number (Tracking No) Filter
                      Expanded(
                          flex: 2,
                          child: Focus(
                              onKeyEvent: (node, event) =>
                                  KeyEventResult.skipRemainingHandlers,
                              child: TextField(
                                controller: _trackingController,
                                decoration: InputDecoration(
                                  hintText: 'AL Number...',
                                  prefixIcon:
                                      const Icon(Icons.qr_code, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                ),
                                onChanged: (v) {
                                  if (_debounceTracking?.isActive ?? false)
                                    _debounceTracking!.cancel();
                                  _debounceTracking = Timer(
                                      const Duration(milliseconds: 500), () {
                                    setState(() => _filterTrackingNo = v);
                                  });
                                },
                              ))),
                      const SizedBox(width: 8),
                      // Smart Sender Filter
                      Expanded(
                          flex: 2,
                          child: Focus(
                              onKeyEvent: (node, event) =>
                                  KeyEventResult.skipRemainingHandlers,
                              child: TextField(
                                controller: _senderController,
                                decoration: InputDecoration(
                                  hintText: 'Sender...',
                                  prefixIcon:
                                      const Icon(Icons.person, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                ),
                                onChanged: (v) {
                                  if (_debounce?.isActive ?? false)
                                    _debounce!.cancel();
                                  _debounce = Timer(
                                      const Duration(milliseconds: 500), () {
                                    setState(() => _filterSenderName = v);
                                  });
                                },
                              ))),
                      const SizedBox(width: 8),
                      // Smart Customer Filter
                      Expanded(
                          flex: 2,
                          child: Focus(
                              onKeyEvent: (node, event) =>
                                  KeyEventResult.skipRemainingHandlers,
                              child: TextField(
                                controller: _customerController,
                                decoration: InputDecoration(
                                  hintText: 'Customer...',
                                  prefixIcon:
                                      const Icon(Icons.business, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                ),
                                onChanged: (v) {
                                  if (_debounceCustomer?.isActive ?? false)
                                    _debounceCustomer!.cancel();
                                  _debounceCustomer = Timer(
                                      const Duration(milliseconds: 500), () {
                                    setState(() => _filterCustomerName = v);
                                  });
                                },
                              ))),
                      const SizedBox(width: 8),
                      // Smart Shipping Method Filter
                      Expanded(
                          flex: 2,
                          child: Focus(
                              onKeyEvent: (node, event) =>
                                  KeyEventResult.skipRemainingHandlers,
                              child: TextField(
                                controller: _shippingController,
                                decoration: InputDecoration(
                                  hintText: 'Shipping Method...',
                                  prefixIcon: const Icon(Icons.local_shipping,
                                      size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                ),
                                onChanged: (v) {
                                  if (_debounceShipping?.isActive ?? false)
                                    _debounceShipping!.cancel();
                                  _debounceShipping = Timer(
                                      const Duration(milliseconds: 500), () {
                                    setState(() => _filterShippingMethod = v);
                                  });
                                },
                              ))),
                      const SizedBox(width: 8),
                      // Smart Remarks Filter
                      Expanded(
                          flex: 2,
                          child: Focus(
                              onKeyEvent: (node, event) =>
                                  KeyEventResult.skipRemainingHandlers,
                              child: TextField(
                                controller: _remarksController,
                                decoration: InputDecoration(
                                  hintText: 'Remarks...',
                                  prefixIcon: const Icon(Icons.notes, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!)),
                                ),
                                onChanged: (v) {
                                  if (_debounceRemarks?.isActive ?? false)
                                    _debounceRemarks!.cancel();
                                  _debounceRemarks = Timer(
                                      const Duration(milliseconds: 500), () {
                                    setState(() => _filterRemarks = v);
                                  });
                                },
                              ))),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _generateReport,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('RUN REPORT'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── ACTION BAR ──
              _buildPrevMonthBanner(),
              if (_draftCount > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200)),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'Note: $_draftCount shipments are hidden because they are currently sitting in Staging Drafts.',
                            style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: 13,
                                fontWeight: FontWeight.w500))),
                  ]),
                ),
              ],
              Row(children: [
                Text('${filtered.length} matching shipments',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo)),
                const SizedBox(width: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.date_range, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('Overview for selected dates: ',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                    Text('$_summaryStagingCount in Staging',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange)),
                    const Text('  |  ', style: TextStyle(color: Colors.grey)),
                    Text('$_summaryBilledCount Billed',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  ]),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: filtered.isEmpty ? null : _exportToExcel,
                  icon: const Icon(Icons.file_download,
                      size: 16, color: Color(0xFF1D6F42)),
                  label: const Text('Export Filtered',
                      style: TextStyle(color: Color(0xFF1D6F42))),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1D6F42)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _selectedShipmentKeys.isEmpty
                      ? null
                      : _generateInvoiceFromSelection,
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: Text(
                      'GENERATE BATCH INVOICE (${_selectedShipmentKeys.length})'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                ),
              ]),
              const SizedBox(height: 12),

              // ── DATA TABLE (Custom Infinite Scroll instead of Pagination) ──
              if (filtered.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8)),
                  height:
                      500, // Fixed height for vertical scrolling to prevent entire page from stretching
                  width: double.infinity,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller:
                          _tableScrollController, // VERTICAL SCROLL for BOTH PANELS
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── LEFT PANEL (Fixed columns) ──
                          SizedBox(
                            width: 280, // 60 + 80 + 140
                            child: Column(
                              children: [
                                // LEFT HEADER
                                Container(
                                  color: Colors.grey[100],
                                  height: 44,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                          width: 60,
                                          child: Checkbox(
                                            value:
                                                _selectedShipmentKeys.length ==
                                                        filtered.length &&
                                                    filtered.isNotEmpty,
                                            onChanged: (v) {
                                              setState(() {
                                                if (v == true) {
                                                  for (var s in filtered)
                                                    _selectedShipmentKeys.add(
                                                        _getShipmentKey(s));
                                                } else {
                                                  for (var s in filtered)
                                                    _selectedShipmentKeys
                                                        .remove(
                                                            _getShipmentKey(s));
                                                }
                                              });
                                            },
                                          )),
                                      Container(
                                          width: 80,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: const Text('ID',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      Container(
                                          width: 140,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: const Text('TRACKING NO',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, thickness: 1),
                                // LEFT ROWS
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount:
                                      _visibleCount.clamp(0, filtered.length),
                                  itemBuilder: (context, index) {
                                    final row = filtered[index];
                                    final key = _getShipmentKey(row);
                                    final isSelected =
                                        _selectedShipmentKeys.contains(key);
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isSelected)
                                            _selectedShipmentKeys.remove(key);
                                          else
                                            _selectedShipmentKeys.add(key);
                                        });
                                      },
                                      child: Container(
                                        height: 48,
                                        color: isSelected
                                            ? Colors.indigo.withOpacity(0.08)
                                            : (index % 2 == 0
                                                ? Colors.white
                                                : Colors.grey[50]),
                                        child: Row(children: [
                                          SizedBox(
                                              width: 60,
                                              child: Checkbox(
                                                value: isSelected,
                                                onChanged: (v) {
                                                  setState(() {
                                                    if (v == true)
                                                      _selectedShipmentKeys
                                                          .add(key);
                                                    else
                                                      _selectedShipmentKeys
                                                          .remove(key);
                                                  });
                                                },
                                              )),
                                          Container(
                                              width: 80,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              child: Text(
                                                  row['id']?.toString() ?? '',
                                                  style: const TextStyle(
                                                      fontSize: 12))),
                                          Container(
                                              width: 140,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              child: Text(
                                                  row['tracking_no']
                                                          ?.toString() ??
                                                      '',
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                  overflow:
                                                      TextOverflow.ellipsis)),
                                        ]),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          // ── RIGHT PANEL (Scrolls horizontally) ──
                          Expanded(
                            child: Scrollbar(
                              controller: _horizontalScrollController,
                              thumbVisibility: true,
                              trackVisibility: true,
                              thickness: 8,
                              radius: const Radius.circular(8),
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // RIGHT HEADER
                                    Container(
                                      color: Colors.grey[100],
                                      height: 44,
                                      child: Row(
                                        children: cols
                                            .where((c) =>
                                                c != 'id' &&
                                                c != 'tracking_no' &&
                                                c != 'source_table')
                                            .map((c) {
                                          double colWidth = 130;
                                          if (c == 'description')
                                            colWidth = 250;
                                          else if (c == 'consignee_name')
                                            colWidth = 180;
                                          return Container(
                                            width: colWidth,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                            child: Text(
                                                c
                                                    .replaceAll('_', ' ')
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    const Divider(height: 1, thickness: 1),
                                    // RIGHT ROWS
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: _visibleCount.clamp(
                                          0, filtered.length),
                                      itemBuilder: (context, index) {
                                        final row = filtered[index];
                                        final key = _getShipmentKey(row);
                                        final isSelected =
                                            _selectedShipmentKeys.contains(key);
                                        return InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (isSelected)
                                                _selectedShipmentKeys
                                                    .remove(key);
                                              else
                                                _selectedShipmentKeys.add(key);
                                            });
                                          },
                                          child: Container(
                                            height: 48,
                                            color: isSelected
                                                ? Colors.indigo
                                                    .withOpacity(0.08)
                                                : (index % 2 == 0
                                                    ? Colors.white
                                                    : Colors.grey[50]),
                                            child: Row(
                                              children: cols
                                                  .where((c) =>
                                                      c != 'id' &&
                                                      c != 'tracking_no' &&
                                                      c != 'source_table')
                                                  .map((c) {
                                                double colWidth = 130;
                                                if (c == 'description')
                                                  colWidth = 250;
                                                else if (c == 'consignee_name')
                                                  colWidth = 180;
                                                return SizedBox(
                                                  width: colWidth,
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8),
                                                    child: Text(
                                                        row[c]?.toString() ??
                                                            '',
                                                        style: const TextStyle(
                                                            fontSize: 12),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No shipments match the selected filters.',
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                )),
            ],
          )),
    );
  }

  // =========================================================================
  // TAB 2 — Staging Drafts
  // =========================================================================
  Widget _buildDraftsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top independent filters for Staging Drafts
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!)),
          child: Row(children: [
            // Start Date
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _stagingStartDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => _stagingStartDate = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd MMM yyyy').format(_stagingStartDate),
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            const Text('to'),
            const SizedBox(width: 8),
            // End Date
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _stagingEndDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => _stagingEndDate = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd MMM yyyy').format(_stagingEndDate),
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _fetchDrafts,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Fetch Drafts'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _exportDraftsToExcel,
              icon: const Icon(Icons.table_view, size: 16),
              label: const Text('Export Filtered'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Universal Search for Drafts
        TextField(
          controller: _draftsSearchController,
          decoration: InputDecoration(
            hintText: 'Search AL Number, Sender, or Invoice...',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!)),
          ),
          onChanged: (v) {
            if (_debounceDrafts?.isActive ?? false) _debounceDrafts!.cancel();
            _debounceDrafts = Timer(const Duration(milliseconds: 500), () {
              setState(() => _filterDraftsText = v);
            });
          },
        ),
        const SizedBox(height: 16),

        if (_isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(
              child: Center(
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red))))
        else if (_filteredDrafts.isEmpty)
          Expanded(
              child: Center(
                  child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pending_actions, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text('No staging drafts found.',
                  style: TextStyle(fontSize: 15, color: Colors.grey[600])),
            ],
          )))
        else ...[
          Row(children: [
            const Icon(Icons.pending_actions, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text('${_filteredDrafts.length} Staging Drafts',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredDrafts.length,
              itemBuilder: (_, i) {
                final d = _filteredDrafts[i];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.orangeAccent)),
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.pending_actions,
                                color: Colors.orange)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('STAGING',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                Text(d.invoiceNumber,
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ]),
                              const SizedBox(height: 4),
                              Text(d.customerName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              Text('${d.items.length} line items',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13)),
                            ])),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('₹${d.totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: Colors.green)),
                              const SizedBox(height: 8),
                              Row(children: [
                                OutlinedButton.icon(
                                  onPressed: () => _revertDraft(d.id),
                                  icon: const Icon(Icons.undo, size: 15),
                                  label: const Text('Revert'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final r = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                NewInvoiceAutomationScreen(
                                                    draftId: d.id)));
                                    if (r == true) _fetchDrafts();
                                  },
                                  icon: const Icon(Icons.edit, size: 15),
                                  label: const Text('Edit'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange,
                                      side: const BorderSide(
                                          color: Colors.orange),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _approveDraft(
                                    d.id,
                                    draftName: d.customerName,
                                    lineItemCount: d.items.length,
                                    totalAmount: d.totalAmount,
                                  ),
                                  icon:
                                      const Icon(Icons.check_circle, size: 15),
                                  label: const Text('Approve'),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                ),
                              ]),
                            ]),
                      ])),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }

// =========================================================================
// TAB 3 — Billed Shipments
// =========================================================================
  Future<void> _exportBilledShipments() async {
    if (_filteredBilledShipments.isEmpty) {
      AppSnackbar.show(context, message: 'No billed shipments to export.');
      return;
    }
    final excel = xlsLib.Excel.createExcel();
    final sheet = excel['Billed Shipments'];

    sheet.appendRow([
      xlsLib.TextCellValue('ID'),
      xlsLib.TextCellValue('TRACKING NO'),
      xlsLib.TextCellValue('INVOICE NO'),
      xlsLib.TextCellValue('CUSTOMER NAME'),
      xlsLib.TextCellValue('SENDER NAME'),
      xlsLib.TextCellValue('SHIPPING METHOD'),
      xlsLib.TextCellValue('ORIGIN'),
      xlsLib.TextCellValue('DESTINATION'),
      xlsLib.TextCellValue('BILLED DATE'),
    ]);

    for (var row in _filteredBilledShipments) {
      sheet.appendRow([
        xlsLib.TextCellValue(row['id']?.toString() ?? ''),
        xlsLib.TextCellValue(row['tracking_no']?.toString() ?? ''),
        xlsLib.TextCellValue(row['invoice_number']?.toString() ?? ''),
        xlsLib.TextCellValue(row['customer_name']?.toString() ?? ''),
        xlsLib.TextCellValue(row['sender_name']?.toString() ?? ''),
        xlsLib.TextCellValue(row['shipping_method']?.toString() ?? ''),
        xlsLib.TextCellValue(row['origin']?.toString() ?? ''),
        xlsLib.TextCellValue(row['destination']?.toString() ?? ''),
        xlsLib.TextCellValue(row['billed_at'] != null
            ? DateFormat('dd/MM/yyyy').format(
                DateTime.tryParse(row['billed_at'].toString()) ??
                    DateTime.now())
            : ''),
      ]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      final blob = html.Blob([bytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download',
            'Billed_Shipments_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  // ── Month-gate banner (Shipment Processing tab) ────────────────────────
  Widget _buildPrevMonthBanner() {
    final s = _prevMonthStatus;
    if (s == null || s['applicable'] != true) return const SizedBox.shrink();
    final total = (s['totalPending'] ?? 0) as int;
    final label = s['monthLabel']?.toString() ?? s['month']?.toString() ?? '';

    // Cleared — nothing pending in the previous month.
    if (total == 0) return const SizedBox.shrink();

    final overridden = s['overridden'] == true;
    final crmChecked = s['crmChecked'] == true;
    final color = overridden ? Colors.blue : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(overridden ? Icons.lock_open : Icons.lock_outline,
            color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              overridden
                  ? '$label had pending shipments — override granted, you can generate invoices.'
                  : 'You are not allowed to generate invoices through automation.',
              style: TextStyle(
                  color: color.shade900,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '$label still has $total pending shipment(s): '
              '${s['pendingInStaging']} in Staging Drafts, '
              '${s['pendingInProcessing']} in Shipment Processing'
              '${crmChecked ? '' : ' (Shipment Processing count unavailable — CRM unreachable)'}.'
              '${overridden ? '\nOverride by ${s['override']?['approvedByEmail'] ?? ''} — ${s['override']?['reason'] ?? ''}' : '\nContact your management for approval.'}',
              style: TextStyle(color: color.shade800, fontSize: 12),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        if (_isApprover && !overridden)
          TextButton(
            onPressed: _grantOverride,
            child: const Text('Grant override'),
          ),
        if (_isApprover)
          TextButton(
            onPressed: _showOverrideHistory,
            child: const Text('History'),
          ),
      ]),
    );
  }

  // ── Manual-billed reconciliation (Billed Shipments tab, admin only) ────
  Future<void> _openManualBilledReconcile() async {
    Map<String, dynamic> data;
    try {
      data = await InvoiceAutomationService.getManualBilledCandidates(
        startDate: DateFormat('yyyy-MM-dd').format(_billedStartDate),
        endDate: DateFormat('yyyy-MM-dd').format(_billedEndDate),
      );
    } catch (e) {
      AppSnackbar.show(context,
          message: 'Failed to load candidates: $e', isError: true);
      return;
    }
    if (!mounted) return;

    final clean = List<Map<String, dynamic>>.from(
        (data['clean'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    final ambiguous = List<Map<String, dynamic>>.from((data['ambiguous'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e)));

    // Selection state
    final Set<String> cleanSelected =
        clean.map((c) => c['trackingNo'].toString()).toSet();
    // trackingNo -> chosen invoiceId ('' = leave it)
    final Map<String, String> ambiguousChoice = {
      for (final a in ambiguous) a['trackingNo'].toString(): ''
    };
    final reasonCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setInner) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Reconcile manually-invoiced shipments'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'These shipments are on a real invoice but were never recorded in '
                    'Billed Shipments, so they still show under Shipment Processing. '
                    'Scoped to ${DateFormat('dd MMM yyyy').format(_billedStartDate)} – '
                    '${DateFormat('dd MMM yyyy').format(_billedEndDate)} '
                    '(change the dates above and re-open to widen).',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),

                  // Clean candidates
                  Text('Clear cases (${clean.length}) — one invoice each',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (clean.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('None.',
                            style: TextStyle(color: Colors.grey))),
                  ...clean.map((c) {
                    final tn = c['trackingNo'].toString();
                    final inv = c['invoice'] as Map<String, dynamic>;
                    return CheckboxListTile(
                      dense: true,
                      value: cleanSelected.contains(tn),
                      onChanged: (v) => setInner(() {
                        if (v == true) {
                          cleanSelected.add(tn);
                        } else {
                          cleanSelected.remove(tn);
                        }
                      }),
                      title: Text('$tn  →  ${inv['invoiceNumber']}'),
                      subtitle: Text(
                          '${inv['customerName'] ?? ''} · ${inv['status'] ?? ''}'
                          '${c['alsoInStagingDraft'] == true ? '  ·  ⚠ also in a Staging Draft' : ''}'),
                    );
                  }),

                  const Divider(height: 24),

                  // Ambiguous candidates
                  Text('Needs a decision (${ambiguous.length}) — on more than one invoice',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (ambiguous.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('None.',
                            style: TextStyle(color: Colors.grey))),
                  ...ambiguous.map((a) {
                    final tn = a['trackingNo'].toString();
                    final invs = List<Map<String, dynamic>>.from(
                        (a['invoices'] as List)
                            .map((e) => Map<String, dynamic>.from(e)));
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.amber.shade300),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.amber.shade50,
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tn,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            if (a['alsoInStagingDraft'] == true)
                              const Text('⚠ also sitting in a Staging Draft',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.red)),
                            RadioListTile<String>(
                              dense: true,
                              value: '',
                              groupValue: ambiguousChoice[tn],
                              onChanged: (v) =>
                                  setInner(() => ambiguousChoice[tn] = v ?? ''),
                              title: const Text('Leave it (do nothing)'),
                            ),
                            ...invs.map((inv) => RadioListTile<String>(
                                  dense: true,
                                  value: inv['invoiceId'].toString(),
                                  groupValue: ambiguousChoice[tn],
                                  onChanged: (v) => setInner(
                                      () => ambiguousChoice[tn] = v ?? ''),
                                  title: Text(
                                      'Bill against ${inv['invoiceNumber']} '
                                      '· ${inv['customerName'] ?? ''} '
                                      '· ₹${inv['totalAmount'] ?? ''} '
                                      '· ${inv['status'] ?? ''}'),
                                )),
                          ]),
                    );
                  }),

                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason (required)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _showManualBilledHistory();
                },
                child: const Text('View history')),
            ElevatedButton(
              onPressed: () async {
                if (reasonCtrl.text.trim().isEmpty) {
                  AppSnackbar.show(ctx,
                      message: 'A reason is required.', isError: true);
                  return;
                }
                final items = <Map<String, dynamic>>[];
                for (final c in clean) {
                  final tn = c['trackingNo'].toString();
                  if (!cleanSelected.contains(tn)) continue;
                  final inv = c['invoice'] as Map<String, dynamic>;
                  items.add({
                    'trackingNo': tn,
                    'invoiceId': inv['invoiceId'],
                    'invoiceNumber': inv['invoiceNumber'],
                    'wasAmbiguous': false,
                  });
                }
                for (final a in ambiguous) {
                  final tn = a['trackingNo'].toString();
                  final chosen = ambiguousChoice[tn] ?? '';
                  if (chosen.isEmpty) continue; // "leave it"
                  final inv = (a['invoices'] as List)
                      .map((e) => Map<String, dynamic>.from(e))
                      .firstWhere((e) => e['invoiceId'].toString() == chosen);
                  items.add({
                    'trackingNo': tn,
                    'invoiceId': inv['invoiceId'],
                    'invoiceNumber': inv['invoiceNumber'],
                    'wasAmbiguous': true,
                  });
                }
                if (items.isEmpty) {
                  AppSnackbar.show(ctx,
                      message: 'Nothing selected to sync.', isError: true);
                  return;
                }
                try {
                  final res = await InvoiceAutomationService.syncManualBilled(
                      items, reasonCtrl.text.trim());
                  Navigator.pop(ctx);
                  AppSnackbar.show(context,
                      message: res['message']?.toString() ??
                          'Synced ${res['inserted']} shipment(s).');
                  _fetchBilledShipments();
                  _generateReport();
                } catch (e) {
                  AppSnackbar.show(ctx, message: 'Sync failed: $e', isError: true);
                }
              },
              child: const Text('Sync to Billed'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showManualBilledHistory() async {
    List<Map<String, dynamic>> rows = [];
    try {
      rows = await InvoiceAutomationService.getManualBilledHistory();
    } catch (e) {
      AppSnackbar.show(context,
          message: 'Failed to load history: $e', isError: true);
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Manual billed — sync history'),
        content: SizedBox(
          width: 600,
          child: rows.isEmpty
              ? const Text('No manual syncs recorded yet.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: rows.map((r) {
                      return ListTile(
                        dense: true,
                        title: Text(
                            '${r['trackingNo']}  →  ${r['invoiceNumber']}'
                            '${r['wasAmbiguous'] == true ? '  (was ambiguous)' : ''}'),
                        subtitle: Text(
                            '${r['performedByEmail'] ?? ''} (${r['performedByRole'] ?? ''})'
                            ' · ${r['createdAt'] ?? ''}\nReason: ${r['reason'] ?? ''}'),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildBilledShipmentsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top independent filters for Billed Shipments
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!)),
          child: Row(children: [
            // Report Type
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _billedSelectedReportType,
                decoration: const InputDecoration(
                    labelText: 'Report Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                items: kReportTypes
                    .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (val) =>
                    setState(() => _billedSelectedReportType = val),
              ),
            ),
            const SizedBox(width: 12),
            // Start Date
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _billedStartDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => _billedStartDate = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd MMM yyyy').format(_billedStartDate),
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            const Text('to'),
            const SizedBox(width: 8),
            // End Date
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _billedEndDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => _billedEndDate = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd MMM yyyy').format(_billedEndDate),
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _fetchBilledShipments,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Fetch Billed'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B2A47),
                  foregroundColor: Colors.white),
            ),
            if (_isApprover) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _openManualBilledReconcile,
                icon: const Icon(Icons.sync_problem, size: 16),
                label: const Text('Reconcile manual invoices'),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // Universal Search for Billed Shipments
        TextField(
          controller: _billedSearchController,
          decoration: InputDecoration(
            hintText: 'Search AL Number, Sender, or Invoice...',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!)),
          ),
          onChanged: (v) {
            if (_debounceBilled?.isActive ?? false) _debounceBilled!.cancel();
            _debounceBilled = Timer(const Duration(milliseconds: 500), () {
              setState(() => _filterBilledText = v);
            });
          },
        ),
        const SizedBox(height: 16),

        if (_isLoadingBilled)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_filteredBilledShipments.isEmpty)
          Expanded(
              child: Center(
                  child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text('No billed shipments found.',
                  style: TextStyle(fontSize: 15, color: Colors.grey[600])),
            ],
          )))
        else ...[
          Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
            const SizedBox(width: 8),
            Text('${_filteredBilledShipments.length} Billed Shipments',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _exportBilledShipments,
              icon: const Icon(Icons.download, size: 16, color: Colors.green),
              label: const Text('Export Filtered',
                  style: TextStyle(color: Colors.green)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.green)),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1370,
                  child: Column(children: [
                    // Header
                    Container(
                      color: Colors.green.shade800,
                      height: 44,
                      child: Row(children: [
                        _billedHeader('ID', 80),
                        _billedHeader('TRACKING NO', 140),
                        _billedHeader('INVOICE NO', 140),
                        _billedHeader('CUSTOMER NAME', 180),
                        _billedHeader('SENDER NAME', 160),
                        _billedHeader('SHIPPING METHOD', 150),
                        _billedHeader('ORIGIN', 150),
                        _billedHeader('DESTINATION', 150),
                        _billedHeader('BILLED DATE', 120),
                        _billedHeader('ACTIONS', 100),
                      ]),
                    ),
                    const Divider(height: 1, thickness: 1),
                    // Rows
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredBilledShipments.length,
                        itemBuilder: (_, i) {
                          final row = _filteredBilledShipments[i];
                          return Container(
                            height: 48,
                            color: i % 2 == 0 ? Colors.white : Colors.grey[50],
                            child: Row(children: [
                              _billedCell(row['id']?.toString() ?? '', 80),
                              _billedCell(
                                  row['tracking_no']?.toString() ?? '', 140),
                              Container(
                                width: 140,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: Colors.green.shade300),
                                  ),
                                  child: Text(
                                      row['invoice_number']?.toString() ?? '',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ),
                              _billedCell(
                                  row['customer_name']?.toString() ?? '', 180),
                              _billedCell(
                                  row['sender_name']?.toString() ?? '', 160),
                              _billedCell(
                                  row['shipping_method']?.toString() ?? '',
                                  150),
                              _billedCell(row['origin']?.toString() ?? '', 150),
                              _billedCell(
                                  row['destination']?.toString() ?? '', 150),
                              _billedCell(
                                  row['billed_at'] != null
                                      ? DateFormat('dd/MM/yyyy').format(
                                          DateTime.tryParse(row['billed_at']
                                                  .toString()) ??
                                              DateTime.now())
                                      : '',
                                  120),
                              if (_currentRole == 'owner' ||
                                  _currentRole == 'admin')
                                SizedBox(
                                  width: 100,
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    tooltip: 'Remove from Billed',
                                    onPressed: () => _revertBilledShipment(
                                        row['tracking_no']?.toString() ?? '',
                                        row['invoice_number']?.toString() ??
                                            ''),
                                  ),
                                )
                              else
                                const SizedBox(width: 100),
                            ]),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _billedHeader(String text, double width) => Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      );

  Widget _billedCell(String text, double width) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(text,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      );
}

// =========================================================================
// DATA SOURCE FOR PAGINATED TABLE
