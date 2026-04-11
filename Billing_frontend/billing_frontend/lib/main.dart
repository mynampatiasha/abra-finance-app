import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:overlay_support/overlay_support.dart';
import 'features/finance_welcome_screen.dart';
import 'features/billing/billing_main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env — never crash if missing
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env loaded');
    debugPrint('📍 FINANCE_API_BASE_URL: ${dotenv.env['FINANCE_API_BASE_URL']}');
  } catch (e) {
    debugPrint('⚠️ .env load failed: $e — using fallback');
    dotenv.testLoad(fileInput: '''
FINANCE_API_BASE_URL=https://finance.abragroup.in
API_BASE_URL=https://fleet.abra-travels.com
''');
  }

  // Global Flutter error handler — prevents white screen crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('❌ Flutter error: ${details.exceptionAsString()}');
  };

  runApp(const AbraFinanceApp());
}

class AbraFinanceApp extends StatelessWidget {
  const AbraFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global(
      child: MaterialApp(
        title: 'Abra Finance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A3A6B)),
          useMaterial3: true,
        ),
        // Suppress red error screens in release
        builder: (context, child) {
          ErrorWidget.builder = (FlutterErrorDetails details) {
            debugPrint('❌ Widget error: ${details.exceptionAsString()}');
            return const SizedBox.shrink();
          };
          return child!;
        },
        home: const FinanceWelcomeScreen(),
        routes: {
          '/finance/dashboard': (_) => const BillingMainShell(),
        },
      ),
    );
  }
}
