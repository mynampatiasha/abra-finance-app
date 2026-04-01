// File: lib/features/TMS/tickets_webview_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class TicketsWebViewScreen extends StatefulWidget {
  final String jwtToken;
  final String initialPage;

  const TicketsWebViewScreen({
    super.key,
    required this.jwtToken,
    required this.initialPage,
  });

  @override
  State<TicketsWebViewScreen> createState() => _TicketsWebViewScreenState();
}

class _TicketsWebViewScreenState extends State<TicketsWebViewScreen> {
  late final WebViewController? _controller;
  bool _isLoading = true;
  String _currentPageTitle = 'Ticket Management System';

  @override
  void initState() {
    super.initState();
    
    if (kIsWeb) {
      // For web, open in new tab instead of WebView
      _openInBrowser();
    } else {
      // For mobile, request permissions and use WebView
      _requestPermissionsAndInitialize();
    }
  }

  /// Request camera and location permissions before initializing WebView
  Future<void> _requestPermissionsAndInitialize() async {
    debugPrint('🔐 ========================================');
    debugPrint('🔐 REQUESTING PERMISSIONS FOR TMS WEBVIEW');
    debugPrint('🔐 ========================================');

    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    debugPrint('📷 Camera permission: $cameraStatus');

    // Request location permission
    final locationStatus = await Permission.location.request();
    debugPrint('📍 Location permission: $locationStatus');

    // Request microphone permission (for WebView media)
    final microphoneStatus = await Permission.microphone.request();
    debugPrint('🎤 Microphone permission: $microphoneStatus');

    // Initialize WebView regardless of permission status
    _initializeWebView();
  }

  void _openInBrowser() async {
    final pageMap = {
      'raise_ticket': 'TMS/raise_ticket.php',
      'my_tickets': 'TMS/my_tickets.php',
      'all_tickets': 'TMS/all_tickets.php',
      'closed_tickets': 'TMS/closed_tickets.php',
    };

    final phpPage = pageMap[widget.initialPage] ?? 'TMS/raise_ticket.php';
    final url = 'https://hrm.fleet.abra-travels.com/index.php?token=${widget.jwtToken}&redirect=$phpPage';
    
    debugPrint('🌐 Opening in browser: $url');
    
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      // Go back after opening browser
      if (mounted) {
        Navigator.pop(context);
      }
    } else {
      debugPrint('❌ Could not launch URL');
    }
  }

  void _initializeWebView() {
    final pageMap = {
      'raise_ticket': 'TMS/raise_ticket.php',
      'my_tickets': 'TMS/my_tickets.php',
      'all_tickets': 'TMS/all_tickets.php',
      'closed_tickets': 'TMS/closed_tickets.php',
    };

    final phpPage = pageMap[widget.initialPage] ?? 'TMS/raise_ticket.php';
    final url = 'https://hrm.fleet.abra-travels.com/index.php?token=${widget.jwtToken}&redirect=$phpPage';
    
    debugPrint('🌐 ========================================');
    debugPrint('🌐 WEBVIEW INITIALIZATION');
    debugPrint('🌐 Initial Page: ${widget.initialPage}');
    debugPrint('🌐 PHP Page: $phpPage');
    debugPrint('🌐 URL: $url');
    debugPrint('🌐 JWT Token: ${widget.jwtToken.substring(0, 20)}...');
    debugPrint('🌐 ========================================');
    
    // Create platform-specific parameters
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller = WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('📄 Page started loading: $url');
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            debugPrint('✅ Page finished loading: $url');
            setState(() => _isLoading = false);
            
            if (url.contains('raise_ticket.php')) {
              setState(() => _currentPageTitle = 'Raise a Ticket');
            } else if (url.contains('my_tickets.php')) {
              setState(() => _currentPageTitle = 'My Tickets');
            } else if (url.contains('all_tickets.php')) {
              setState(() => _currentPageTitle = 'All Tickets');
            } else if (url.contains('closed_tickets.php')) {
              setState(() => _currentPageTitle = 'Closed Tickets');
            }
          },
          onWebResourceError: (error) {
            debugPrint('❌ WebView Error: ${error.description}');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error loading page: ${error.description}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    // ✅ ANDROID-SPECIFIC: Enable geolocation and camera permissions
    // Only configure Android-specific features on mobile platforms
    if (!kIsWeb && controller.platform is AndroidWebViewController) {
      debugPrint('🤖 Configuring Android WebView permissions...');
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController).setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          debugPrint('📍 Geolocation permission requested by WebView');
          debugPrint('📍 Origin: ${request.origin}');
          
          // Grant geolocation permission
          return GeolocationPermissionsResponse(
            allow: true,
            retain: true,
          );
        },
      );

      // Enable camera, microphone, and other media permissions
      // Note: setOnPermissionRequest is not available in webview_flutter_android 3.16.9
      // Permissions are handled through Android manifest and system prompts
      debugPrint('🔐 Android WebView configured - permissions handled by system');
    }

    // ✅ iOS-SPECIFIC: Configure WKWebView for media permissions
    if (controller.platform is WebKitWebViewController) {
      debugPrint('🍎 Configuring iOS WKWebView permissions...');
      // iOS handles permissions through Info.plist and system prompts
      // No additional configuration needed here
    }

    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    // If web, show message instead of WebView
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ticket System'),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.open_in_browser, size: 64, color: Color(0xFF0D47A1)),
              const SizedBox(height: 24),
              const Text(
                'Opening Ticket System',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'The ticket system has been opened in your browser.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile WebView
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPageTitle),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            debugPrint('🔙 Back button pressed');
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              debugPrint('🔄 Refresh button pressed');
              _controller?.reload();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading Ticket System...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
