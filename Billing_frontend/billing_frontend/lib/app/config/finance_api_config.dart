import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FinanceApiConfig {
  static String get baseUrl {
    final envUrl = dotenv.env['FINANCE_API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      if (kDebugMode) print('✅ FinanceApiConfig using .env: $envUrl');
      return envUrl;
    }
    return 'https://finance.abragroup.in';
  }
}
