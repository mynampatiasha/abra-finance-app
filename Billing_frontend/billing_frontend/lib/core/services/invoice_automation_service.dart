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
}
