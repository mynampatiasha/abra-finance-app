import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, kReleaseMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static const String _productionUrl = 'https://finance.abragroup.in';
  static const String _localPhoneUrl = 'http://192.168.1.8:3002';
  static const String _webUrl = 'http://localhost:3002';

  static String get baseUrl {
    // 1. If .env has a value, always use it (manual override)
    final envUrl = dotenv.env['FINANCE_API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      if (kDebugMode) print('✅ Using .env URL: $envUrl');
      return envUrl;
    }

    // 2. Only use production when building RELEASE
    if (kReleaseMode) {
      return _productionUrl;
    }

    // 3. Debug AND Profile mode = local development
    if (kIsWeb) return _webUrl;        // Chrome → localhost
    return _localPhoneUrl;             // Phone → 192.168.1.8
  }

  static String get wsUrl {
    final envUrl = dotenv.env['FINANCE_WEBSOCKET_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;

    if (kReleaseMode) return 'wss://finance.abragroup.in';
    if (kIsWeb) return 'ws://localhost:3002';
    return 'ws://192.168.1.8:3002';
  }

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