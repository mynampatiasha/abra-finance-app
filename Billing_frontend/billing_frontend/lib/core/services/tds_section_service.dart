// ============================================================================
// TDS SECTION SERVICE
// ============================================================================
// File: lib/core/services/tds_section_service.dart
// Fetches the org's TDS Section master list (name + default rate) used by the
// invoice form's TDS dropdown, e.g. "Commission or Brokerage [2%]".
// ============================================================================

import '../../core/services/api_service.dart';

class TdsSection {
  final String id;
  final String name;
  final double rate;

  TdsSection({required this.id, required this.name, required this.rate});

  factory TdsSection.fromJson(Map<String, dynamic> json) {
    return TdsSection(
      id: (json['_id'] ?? '').toString(),
      name: json['name'] ?? '',
      rate: (json['rate'] ?? 0).toDouble(),
    );
  }
}

class TdsSectionService {
  static final ApiService _api = ApiService();
  static const String _baseEndpoint = '/api/finance/tds-sections';

  static Future<List<TdsSection>> getSections() async {
    try {
      final data = await _api.get(_baseEndpoint);
      final list = (data['data']?['sections'] as List?) ?? [];
      return list.map((s) => TdsSection.fromJson(s)).toList();
    } catch (e) {
      print('❌ Error fetching TDS sections: $e');
      return [];
    }
  }

  static Future<bool> addSection(String name, double rate) async {
    try {
      await _api.post(_baseEndpoint, body: {'name': name, 'rate': rate});
      return true;
    } catch (e) {
      print('❌ Error adding TDS section: $e');
      return false;
    }
  }
}
