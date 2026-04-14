import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static String get baseUrl {
    final envUrl = dotenv.env['FINANCE_API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      if (kDebugMode) print('✅ ApiConfig (finance) using .env: $envUrl');
      return envUrl;
    }
    return 'https://finance.abragroup.in';
  }

  static String get wsUrl {
    final envUrl = dotenv.env['FINANCE_WEBSOCKET_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
    return 'wss://finance.abragroup.in';
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
