// lib/app/config/finance_api_config.dart
// Mirrors ApiConfig from abra_fleet — same pattern, port 3002

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FinanceApiConfig {
  /// Reads FINANCE_API_BASE_URL from .env.
  /// Falls back to localhost:3002 (web) or 10.0.2.2:3002 (emulator).
  static String get baseUrl {
    final envUrl = dotenv.env['FINANCE_API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      if (kDebugMode) print('✅ FinanceApiConfig using .env: $envUrl');
      return envUrl;
    }

    // Fallback
    if (kIsWeb) {
      const url = 'http://localhost:3002';
      if (kDebugMode) print('⚠️  FinanceApiConfig fallback (web): $url');
      return url;
    } else {
      // Android emulator → 10.0.2.2, physical device → set FINANCE_API_BASE_URL in .env
      const url = 'http://10.0.2.2:3002';
      if (kDebugMode) print('⚠️  FinanceApiConfig fallback (mobile): $url');
      return url;
    }
  }
}
