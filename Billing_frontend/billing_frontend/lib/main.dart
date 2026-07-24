import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:overlay_support/overlay_support.dart';
import 'core/finance_secure_storage.dart';
import 'features/finance_welcome_screen.dart';
import 'features/billing/billing_main_shell.dart';

// ─── Global navigator key ─────────────────────────────────────────────────────
// Used by handleTokenExpired() to navigate from anywhere (e.g. API service)
// without needing a BuildContext.
final GlobalKey<NavigatorState> financeNavigatorKey =
    GlobalKey<NavigatorState>();

// ─── Global token-expired handler ────────────────────────────────────────────
// Call this from any API response handler when a 401/TOKEN_EXPIRED is received.
// Clears the session and sends the user back to the welcome screen.
Future<void> handleTokenExpired() async {
  await FinanceSecureStorage.clearSession();
  final nav = financeNavigatorKey.currentState;
  if (nav == null) return;
  // Remove every route and replace with welcome screen
  nav.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const FinanceWelcomeScreen()),
    (route) => false,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env — never crash if missing
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env loaded');
    debugPrint(
        '📍 FINANCE_API_BASE_URL: ${dotenv.env['FINANCE_API_BASE_URL']}');
  } catch (e) {
    debugPrint('⚠️ .env load failed: $e — using fallback');
    dotenv.testLoad(fileInput: '''
FINANCE_API_BASE_URL=http://localhost:3002
API_BASE_URL=http://localhost:3002
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
        navigatorKey: financeNavigatorKey,
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
        home: const _AuthGate(),
        routes: {
          '/finance/dashboard': (_) => const BillingMainShell(),
        },
      ),
    );
  }
}

// ─── Auth Gate ────────────────────────────────────────────────────────────────
// On every cold start / web reload, checks secure storage for a valid token.
// If found → go straight to BillingMainShell (skip welcome + login).
// If not   → show FinanceWelcomeScreen as normal.
// ─────────────────────────────────────────────────────────────────────────────
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final isLoggedIn = await FinanceSecureStorage.isLoggedIn();
      if (!mounted) return;

      if (isLoggedIn) {
        // Token exists — go directly to the main shell
        debugPrint('✅ AuthGate: token found, navigating to dashboard');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BillingMainShell()),
        );
      } else {
        // No token — show welcome screen
        debugPrint('ℹ️ AuthGate: no token, showing welcome screen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FinanceWelcomeScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ AuthGate error: $e — falling back to welcome screen');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FinanceWelcomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Shown for the brief moment while the async check runs
    return const Scaffold(
      backgroundColor: Color(0xFF0D1B3E),
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF3D8EFF),
          strokeWidth: 2,
        ),
      ),
    );
  }
}
