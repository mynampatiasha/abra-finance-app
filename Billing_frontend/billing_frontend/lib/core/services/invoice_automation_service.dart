import 'api_service.dart';
import 'invoice_service.dart' show Invoice;

class InvoiceAutomationService {
  static final ApiService _api = ApiService();

  // ==========================================================================
  // INVOICE AUTOMATION
  // ==========================================================================

  static Future<Map<String, dynamic>> getUnbilledShipments(
      {String? orgId,
      String? branchId,
      String? startDate,
      String? endDate,
      String? reportType}) async {
    final queryParams = <String, String>{};
    if (orgId != null) queryParams['orgId'] = orgId;
    if (branchId != null) queryParams['branchId'] = branchId;
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;
    if (reportType != null) queryParams['reportType'] = reportType;
    final data = await _api.get(
        '/api/finance/invoices-automation/unbilled-shipments',
        queryParams: queryParams);
    return data;
  }

  static Future<Invoice> saveAutomationDraft(
      Map<String, dynamic> invoiceData) async {
    final data = await _api.post('/api/finance/invoices-automation/draft',
        body: invoiceData);
    return Invoice.fromJson(data['invoice']);
  }

  static Future<List<Invoice>> getAutomationDrafts() async {
    final data = await _api.get('/api/finance/invoices-automation/drafts');
    return (data['invoices'] as List).map((i) => Invoice.fromJson(i)).toList();
  }

  static Future<Invoice> updateAutomationDraft(
      String draftId, Map<String, dynamic> invoiceData) async {
    final data = await _api.put(
        '/api/finance/invoices-automation/draft/$draftId',
        body: invoiceData);
    return Invoice.fromJson(data['invoice']);
  }

  static Future<Invoice> approveAutomationDraft(String draftId) async {
    final data =
        await _api.post('/api/finance/invoices-automation/approve/$draftId');
    return Invoice.fromJson(data['invoice']);
  }

  static Future<Map<String, dynamic>> getBilledShipments(
      {String? startDate, String? endDate, String? reportType}) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;
    if (reportType != null) queryParams['reportType'] = reportType;
    final data = await _api.get(
        '/api/finance/invoices-automation/billed-shipments',
        queryParams: queryParams);
    return data;
  }

  static Future<void> deleteAutomationDraft(String draftId) async {
    await _api.delete('/api/finance/invoices-automation/draft/$draftId');
  }

  static Future<void> deleteBilledShipment(String trackingNo) async {
    await _api
        .delete('/api/finance/invoices-automation/billed-shipment/$trackingNo');
  }

  // ── Month gating ─────────────────────────────────────────────────────────

  /// Previous-month pending status for a given "from" date (yyyy-MM-dd).
  /// reportType should match whatever is currently selected on the Shipment
  /// Processing screen — the CRM API requires a non-empty report_type or it
  /// rejects the request outright (looks like "unreachable" if omitted).
  static Future<Map<String, dynamic>> getPrevMonthStatus(String fromDate,
      {String? reportType}) async {
    final data = await _api.get(
      '/api/finance/invoices-automation/prev-month-status',
      queryParams: {
        'fromDate': fromDate,
        if (reportType != null) 'reportType': reportType,
      },
    );
    return Map<String, dynamic>.from(data);
  }

  /// owner/admin only — grant an override for a "YYYY-MM" month.
  static Future<Map<String, dynamic>> createMonthOverride(
      String month, String reason) async {
    final data = await _api.post(
      '/api/finance/invoices-automation/month-override',
      body: {'month': month, 'reason': reason},
    );
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>> getMonthOverrides() async {
    final data =
        await _api.get('/api/finance/invoices-automation/month-overrides');
    return List<Map<String, dynamic>>.from(
        (data['overrides'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<void> revokeMonthOverride(String id) async {
    await _api.delete('/api/finance/invoices-automation/month-override/$id');
  }

  // ── Manual-billed reconciliation ─────────────────────────────────────────

  static Future<Map<String, dynamic>> getManualBilledCandidates(
      {String? startDate, String? endDate}) async {
    final qp = <String, String>{};
    if (startDate != null) qp['startDate'] = startDate;
    if (endDate != null) qp['endDate'] = endDate;
    final data = await _api.get(
        '/api/finance/invoices-automation/manual-billed-candidates',
        queryParams: qp);
    return Map<String, dynamic>.from(data);
  }

  /// owner/admin only — items: [{trackingNo, invoiceId, invoiceNumber, wasAmbiguous}]
  static Future<Map<String, dynamic>> syncManualBilled(
      List<Map<String, dynamic>> items, String reason) async {
    final data = await _api.post(
      '/api/finance/invoices-automation/manual-billed-sync',
      body: {'items': items, 'reason': reason},
    );
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>> getManualBilledHistory() async {
    final data = await _api
        .get('/api/finance/invoices-automation/manual-billed-history');
    return List<Map<String, dynamic>>.from(
        (data['history'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
  }
}
