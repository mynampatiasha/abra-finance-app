// lib/app/config/api_config.dart
// Finance module — mirrors abra_fleet ApiConfig but uses FINANCE_API_BASE_URL / port 3002

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static String get baseUrl {
    final envUrl = dotenv.env['FINANCE_API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      if (kDebugMode) print('✅ ApiConfig (finance) using .env: $envUrl');
      return envUrl;
    }
    final fallback = kIsWeb ? 'http://localhost:3002' : 'http://10.0.2.2:3002';
    if (kDebugMode) print('⚠️  ApiConfig (finance) fallback: $fallback');
    return fallback;
  }

  static String get wsUrl {
    final envUrl = dotenv.env['FINANCE_WEBSOCKET_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
    return kIsWeb ? 'ws://localhost:3002' : 'ws://10.0.2.2:3002';
  }

  // Timeout configurations
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

extension DotEnvExtension on DotEnv {
  bool get isInitialized {
    try {
      return env.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
