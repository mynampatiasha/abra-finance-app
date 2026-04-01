// lib/core/services/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic error;
  final Map<String, dynamic>? details;

  ApiException(this.message, [this.statusCode, this.error, this.details]);

  @override
  String toString() {
    if (details != null) {
      try {
        final errorResponse = {
          'message': message,
          'statusCode': statusCode,
          'error': error,
          'details': details,
        };
        return 'ApiException: ${jsonEncode(errorResponse)}';
      } catch (e) {
        return 'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
      }
    }
    return 'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
  }
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  late final String _baseUrl;

  void _agentLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
    try {
      final payload = jsonEncode({
        'sessionId': 'debug-session',
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      File(r'd:\Documents\Fleet_Management\.cursor\debug.log')
          .writeAsStringSync('$payload\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
  
  // JWT token storage key
  static const String _tokenKey = 'jwt_token';
  
  String? _cachedToken;
  DateTime? _tokenCacheTime;
  Future<String?>? _tokenRequest;
  
  factory ApiService() => _instance;
  
  ApiService._internal() {
    _baseUrl = ApiConfig.baseUrl;
    
    // 🔍 COMPREHENSIVE URL DEBUGGING
    debugPrint('\n' + '🌐' * 80);
    debugPrint('🌐 API SERVICE INITIALIZATION DEBUG (JWT MODE)');
    debugPrint('🌐' * 80);
    debugPrint('📍 Environment loaded: ${dotenv.isInitialized}');
    debugPrint('📍 Raw env value: "${dotenv.env['API_BASE_URL']}"');
    debugPrint('📍 Final base URL: "$_baseUrl"');
    debugPrint('📍 URL length: ${_baseUrl.length}');
    debugPrint('📍 URL starts with http: ${_baseUrl.startsWith('http')}');
    debugPrint('📍 URL contains localhost: ${_baseUrl.contains('localhost')}');
    debugPrint('📍 URL contains 3001: ${_baseUrl.contains('3001')}');
    debugPrint('🌐' * 80 + '\n');
    
    _agentLog(
      'api_service.dart:constructor',
      'ApiService initialized with base URL (JWT mode)',
      {'baseUrl': _baseUrl, 'envValue': dotenv.env['API_BASE_URL']},
      'H1',
    );
    debugPrint('🔧 ApiService: Using base URL: $_baseUrl (JWT Authentication)');
  }

  // Getter for base URL
  String get baseUrl => _baseUrl;

  // Clear token cache (for JWT)
  void clearTokenCache() {
    debugPrint('🧹 Clearing JWT token cache');
    _cachedToken = null;
    _tokenCacheTime = null;
    _tokenRequest = null;
  }

  // Set auth token manually (for compatibility)
  void setAuthToken(String token) {
    debugPrint('🔐 Setting JWT token manually');
    _cachedToken = token;
    _tokenCacheTime = DateTime.now();
  }

  // Clear auth token (for compatibility)
  void clearAuthToken() {
    debugPrint('🧹 Clearing JWT token manually');
    clearTokenCache();
  }

  // ✅ JWT TOKEN HANDLING - Get headers with JWT token (public for multipart requests)
  Future<Map<String, String>> getHeaders({bool forceRefresh = false}) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    try {
      debugPrint('🔐 Getting JWT token...');
      final startTime = DateTime.now();
      
      // ✅ CHECK CACHE FIRST (but skip if forceRefresh is true)
      final now = DateTime.now();
      if (!forceRefresh && 
          _cachedToken != null && 
          _tokenCacheTime != null && 
          now.difference(_tokenCacheTime!).inMinutes < 50) {
        debugPrint('✅ Using cached JWT token');
        headers['Authorization'] = 'Bearer $_cachedToken';
        return headers;
      }
      
      // ✅ If forceRefresh, clear the cache
      if (forceRefresh) {
        debugPrint('🔄 Force refresh requested - clearing token cache');
        clearTokenCache();
      }
      
      // ✅ PREVENT MULTIPLE SIMULTANEOUS TOKEN REQUESTS
      if (_tokenRequest != null) {
        debugPrint('⏳ Waiting for existing token request...');
        final token = await _tokenRequest!;
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
        return headers;
      }
      
      // ✅ GET JWT TOKEN FROM STORAGE
      _tokenRequest = _getStoredToken().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('❌ JWT token retrieval timeout after 10 seconds');
          throw Exception('JWT token retrieval timeout');
        },
      );
      
      final jwtToken = await _tokenRequest!;
      
      // ✅ CACHE THE TOKEN (only if not null)
      if (jwtToken != null && jwtToken.isNotEmpty) {
        _cachedToken = jwtToken;
        _tokenCacheTime = now;
        headers['Authorization'] = 'Bearer $jwtToken';
        
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime).inMilliseconds;
        debugPrint('✅ JWT token retrieved and cached in ${duration}ms');
      } else {
        debugPrint('⚠️ No JWT token found in storage');
      }
      
      _tokenRequest = null;
    } catch (e) {
      _tokenRequest = null;
      debugPrint('❌ CRITICAL: Could not get JWT token: $e. Request will be unauthorized.');
    }
    
    return headers;
  }

  // Get stored JWT token
  Future<String?> _getStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      debugPrint('❌ Error getting stored JWT token: $e');
      return null;
    }
  }

  // ✅ PUBLIC METHOD: Get JWT token (for external use like multipart uploads)
  Future<String?> getToken() async {
    try {
      // Check cache first
      final now = DateTime.now();
      if (_cachedToken != null && 
          _tokenCacheTime != null && 
          now.difference(_tokenCacheTime!).inMinutes < 50) {
        return _cachedToken;
      }
      
      // Get from storage
      final token = await _getStoredToken();
      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
        _tokenCacheTime = now;
      }
      return token;
    } catch (e) {
      debugPrint('❌ Error in getToken(): $e');
      return null;
    }
  }

  // ✅ RETRY WRAPPER FOR 403 ERRORS - Automatic token refresh and retry
  Future<Map<String, dynamic>> _requestWithRetry(
    Future<Map<String, dynamic>> Function() request,
    {int maxRetries = 1}
  ) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await request();
      } catch (e) {
        if (e is ApiException && 
            e.statusCode == 403 && 
            attempt < maxRetries) {
          debugPrint('🔄 Retrying request after 403 error (attempt ${attempt + 1})');
          clearTokenCache(); // Clear token cache
          await Future.delayed(Duration(milliseconds: 500)); // Brief delay
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Max retries exceeded');
  }

  // Generic GET request
  // Generic GET request with automatic 403 retry
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? queryParams}) async {
    return await _requestWithRetry(() async {
      try {
        var uri = Uri.parse('$_baseUrl$endpoint');
        
        if (queryParams != null && queryParams.isNotEmpty) {
          final cleanParams = Map<String, String>.from(queryParams)
            ..removeWhere((key, value) => value.isEmpty);
          
          if (cleanParams.isNotEmpty) {
            uri = uri.replace(queryParameters: cleanParams);
          }
        }
        
        debugPrint('🌐 GET: $uri');
        debugPrint('🔧 Base URL: $_baseUrl');
        debugPrint('🔧 Full URI: $uri');
        
        debugPrint('🔐 Getting headers...');
        final headersStartTime = DateTime.now();
        final headers = await getHeaders();
        final headersEndTime = DateTime.now();
        final headersDuration = headersEndTime.difference(headersStartTime).inMilliseconds;
        
        debugPrint('🔧 Headers retrieved in ${headersDuration}ms: $headers');
        
        debugPrint('📡 Making HTTP request...');
        final requestStartTime = DateTime.now();
        
        final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 100),
          onTimeout: () {
            final requestEndTime = DateTime.now();
            final requestDuration = requestEndTime.difference(requestStartTime).inMilliseconds;
            debugPrint('❌ Request timed out after 100 seconds (actual: ${requestDuration}ms)');
            debugPrint('❌ URI: $uri');
            debugPrint('❌ Headers: $headers');
            throw Exception('Request timeout - Backend may be unreachable');
          },
        );
        
        final requestEndTime = DateTime.now();
        final requestDuration = requestEndTime.difference(requestStartTime).inMilliseconds;
        
        debugPrint('🔧 Response received in ${requestDuration}ms, status: ${response.statusCode}');
        
        return _handleResponse(response);
      } catch (e) {
        debugPrint('❌ GET Error: $e');
        debugPrint('❌ Error type: ${e.runtimeType}');
        debugPrint('❌ Base URL was: $_baseUrl');
        
        if (e is ApiException) {
          rethrow;
        }
        throw ApiException('Network error during GET request', null, e);
      }
    });
  }

  Future<Map<String, dynamic>> post(String endpoint, {Map<String, dynamic>? body}) async {
  try {
    final uri = Uri.parse('$_baseUrl$endpoint');
    debugPrint('\n' + '=' * 80);
    debugPrint('🌐 POST REQUEST STARTING');
    debugPrint('=' * 80);
    debugPrint('🔧 Base URL: $_baseUrl');
    debugPrint('🔧 Endpoint: $endpoint');
    debugPrint('🔧 Full URI: $uri');
    
    if (body != null) {
      debugPrint('📦 Request Body: ${jsonEncode(body)}');
    }
    
    debugPrint('🔐 Getting headers...');
    final headersStartTime = DateTime.now();
    
    // ✅ FIX: Skip token retrieval for login/register endpoints
    Map<String, String> headers;
    if (endpoint == '/api/auth/login' || 
        endpoint == '/api/auth/register' || 
        endpoint == '/api/auth/forgot-password') {
      debugPrint('⚠️ Auth endpoint detected - skipping token retrieval');
      headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
    } else {
      debugPrint('🔐 Regular endpoint - getting token from storage');
      headers = await getHeaders();
    }
    
    final headersEndTime = DateTime.now();
    final headersDuration = headersEndTime.difference(headersStartTime).inMilliseconds;
    
    debugPrint('🔧 Headers retrieved in ${headersDuration}ms');
    debugPrint('📋 Headers: $headers');
    
    debugPrint('📡 Making HTTP POST request...');
    final requestStartTime = DateTime.now();
    
    final response = await http.post(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(
      const Duration(seconds: 100),
      onTimeout: () {
        final requestEndTime = DateTime.now();
        final requestDuration = requestEndTime.difference(requestStartTime).inMilliseconds;
        debugPrint('❌ POST Request timed out after 100 seconds (actual: ${requestDuration}ms)');
        throw Exception('Request timeout - Backend may be unreachable');
      },
    );
    
    final requestEndTime = DateTime.now();
    final requestDuration = requestEndTime.difference(requestStartTime).inMilliseconds;
    
    debugPrint('=' * 80);
    debugPrint('📥 RESPONSE RECEIVED');
    debugPrint('=' * 80);
    debugPrint('⏱️  Response time: ${requestDuration}ms');
    debugPrint('📊 Status: ${response.statusCode}');
    debugPrint('📏 Body length: ${response.body.length}');
    debugPrint('📦 Body: ${response.body}');
    debugPrint('=' * 80);
    
    // Handle the response
    final result = _handleResponse(response);
    
    // ✅ CRITICAL: Log the result structure
    debugPrint('=' * 80);
    debugPrint('🎯 RESPONSE PARSED');
    debugPrint('=' * 80);
    debugPrint('Type: ${result.runtimeType}');
    debugPrint('Keys: ${result.keys.toList()}');
    if (result['data'] != null) {
      debugPrint('Data exists: YES');
      if (result['data'] is Map) {
        debugPrint('Data keys: ${(result['data'] as Map).keys.toList()}');
        if ((result['data'] as Map).containsKey('token')) {
          final token = (result['data'] as Map)['token'];
          debugPrint('Token exists: YES');
          debugPrint('Token length: ${token.toString().length}');
        } else {
          debugPrint('Token exists: NO ❌');
        }
      }
    } else {
      debugPrint('Data exists: NO ❌');
    }
    debugPrint('=' * 80 + '\n');
    
    return result;
    
  } catch (e, stackTrace) {
    debugPrint('\n' + '=' * 80);
    debugPrint('❌ POST ERROR');
    debugPrint('=' * 80);
    debugPrint('Error: $e');
    debugPrint('Type: ${e.runtimeType}');
    debugPrint('Endpoint: $endpoint');
    debugPrint('Stack:');
    debugPrint(stackTrace.toString());
    debugPrint('=' * 80 + '\n');
    
    if (e is ApiException) {
      rethrow;
    }
    throw ApiException('Network error during POST request', null, e);
  }
}

  Future<Map<String, dynamic>> put(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('🌐 PUT: $uri');
      
      final headers = await getHeaders();
      final response = await http.put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(
        const Duration(seconds: 100),
        onTimeout: () {
          debugPrint('❌ PUT Request timed out after 100 seconds');
          debugPrint('❌ URI: $uri');
          throw Exception('Request timeout - Backend may be unreachable');
        },
      );
      
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ PUT Error: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Network error during PUT request', null, e);
    }
  }

  Future<Map<String, dynamic>> patch(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('🌐 PATCH: $uri');
      
      final headers = await getHeaders();
      final response = await http.patch(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(
        const Duration(seconds: 100),
        onTimeout: () {
          debugPrint('❌ PATCH Request timed out after 100 seconds');
          debugPrint('❌ URI: $uri');
          throw Exception('Request timeout - Backend may be unreachable');
        },
      );
      
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ PATCH Error: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Network error during PATCH request', null, e);
    }
  }

  Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('🌐 DELETE: $uri');
      
      final headers = await getHeaders();
      final response = await http.delete(uri, headers: headers).timeout(
        const Duration(seconds: 100),
        onTimeout: () {
          debugPrint('❌ DELETE Request timed out after 100 seconds');
          debugPrint('❌ URI: $uri');
          throw Exception('Request timeout - Backend may be unreachable');
        },
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ DELETE Error: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Network error during DELETE request', null, e);
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    debugPrint('📡 Response Status: ${response.statusCode}');
    
    // ✅ ENHANCED ERROR HANDLING FOR 403 FORBIDDEN
    if (response.statusCode == 403) {
      debugPrint('🔄 403 Forbidden - Token may be expired, clearing cache');
      clearTokenCache(); // Clear cached token
      
      String errorMessage = 'Authentication expired. Please try again.';
      try {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorBody['message'] ?? errorMessage;
      } catch (e) {
        // Use default message if JSON parsing fails
      }
      
      throw ApiException(
        errorMessage,
        response.statusCode,
        'TOKEN_EXPIRED'
      );
    }
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw ApiException('Invalid JSON response', response.statusCode, e);
      }
    } else {
      String errorMessage = 'Request failed';
      Map<String, dynamic>? errorDetails;
      String? errorType;
      
      try {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorBody['message'] ?? errorBody['error'] ?? errorMessage;
        errorType = errorBody['error'];
        errorDetails = errorBody['details'];
        
        debugPrint('❌ Backend Error: $errorMessage');
        if (errorDetails != null) {
          debugPrint('📋 Error Details: ${errorDetails.toString()}');
        }
      } catch (e) {
        errorMessage = response.body.isNotEmpty ? response.body : errorMessage;
        debugPrint('❌ Error parsing response: $e');
      }
      
      throw ApiException(errorMessage, response.statusCode, errorType, errorDetails);
    }
  }

  Future<bool> checkHealth() async {
    try {
      await get('/health');
      return true;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }

  // Future<Map<String, dynamic>> loginToBackend({
  //   required String firebaseUid,
  //   required String email,
  //   String? name,
  //   String? role,
  // }) async {
  //   final body = {
  //     'firebaseUid': firebaseUid,
  //     'email': email,
  //     'name': name,
  //   };
  //   if (role != null) {
  //     body['role'] = role;
  //   }
  //   return await post('/api/auth/login', body: body);
  // }

  Future<Map<String, dynamic>> getProfile() async {
    return await get('/api/auth/profile');
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? phone,
    String? organizationId,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phone != null) body['phone'] = phone;
    if (organizationId != null) body['organizationId'] = organizationId;
    
    return await put('/api/auth/profile', body: body);
  }

  Future<void> updateFcmToken(String fcmToken) async {
    await post('/api/auth/fcm-token', body: {
      'fcmToken': fcmToken,
    });
  }

  Future<void> logout() async {
    _cachedToken = null;
    _tokenCacheTime = null;
    _tokenRequest = null;
    
    debugPrint('Successfully cleared JWT token cache.');
  }

  // Vehicle endpoints
  Future<List<Map<String, dynamic>>> getVehicles() async {
    final response = await get('/api/vehicles');
    return List<Map<String, dynamic>>.from(response['vehicles'] ?? response['data'] ?? []);
  }

  Future<Map<String, dynamic>> getVehicle(String vehicleId) async {
    return await get('/api/vehicles/$vehicleId');
  }

  Future<Map<String, dynamic>> createVehicle(Map<String, dynamic> vehicleData) async {
    return await post('/api/vehicles', body: vehicleData);
  }

  Future<Map<String, dynamic>> updateVehicle(String vehicleId, Map<String, dynamic> vehicleData) async {
    return await put('/api/vehicles/$vehicleId', body: vehicleData);
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await delete('/api/vehicles/$vehicleId');
  }

  // Driver endpoints
  Future<List<Map<String, dynamic>>> getDrivers() async {
    final response = await get('/api/drivers');
    return List<Map<String, dynamic>>.from(response['drivers'] ?? response['data'] ?? []);
  }

  Future<Map<String, dynamic>> getDriver(String driverId) async {
    return await get('/api/drivers/$driverId');
  }

  Future<Map<String, dynamic>> createDriver(Map<String, dynamic> driverData) async {
    return await post('/api/drivers', body: driverData);
  }

  Future<Map<String, dynamic>> updateDriver(String driverId, Map<String, dynamic> driverData) async {
    return await put('/api/drivers/$driverId', body: driverData);
  }

  Future<void> deleteDriver(String driverId) async {
    await delete('/api/drivers/$driverId');
  }

  // Trip endpoints
  Future<List<Map<String, dynamic>>> getTrips() async {
    final response = await get('/api/trips');
    return List<Map<String, dynamic>>.from(response['trips'] ?? response['data'] ?? []);
  }

  Future<Map<String, dynamic>> getTrip(String tripId) async {
    return await get('/api/trips/$tripId');
  }

  Future<Map<String, dynamic>> createTrip(Map<String, dynamic> tripData) async {
    return await post('/api/trips/create', body: tripData);
  }

  Future<Map<String, dynamic>> updateTrip(String tripId, Map<String, dynamic> tripData) async {
    return await put('/api/trips/$tripId', body: tripData);
  }

  Future<void> deleteTrip(String tripId) async {
    await delete('/api/trips/$tripId');
  }

  // Customer Stats endpoints
  Future<Map<String, dynamic>> getCustomerStats() async {
    return await get('/api/customer/stats');
  }

  Future<Map<String, dynamic>> getCustomerDashboardStats() async {
    return await get('/api/customer/stats/dashboard');
  }

  Future<Map<String, dynamic>> getCustomerTripStats() async {
    return await get('/api/customer/stats/trips');
  }

  Future<List<Map<String, dynamic>>> getCustomerMonthlyDistance({int months = 6}) async {
    final response = await get('/api/customer/stats/distance', queryParams: {
      'months': months.toString(),
    });
    return List<Map<String, dynamic>>.from(response['data'] ?? response);
  }

  Future<List<int>> getCustomerServiceFrequency({int weeks = 12}) async {
    final response = await get('/api/customer/stats/frequency', queryParams: {
      'weeks': weeks.toString(),
    });
    return List<int>.from(response['data'] ?? response);
  }

  Future<List<Map<String, dynamic>>> getCustomerTopRoutes({int limit = 3}) async {
    final response = await get('/api/customer/stats/routes', queryParams: {
      'limit': limit.toString(),
    });
    return List<Map<String, dynamic>>.from(response['data'] ?? response);
  }

  Future<Map<String, dynamic>> getCustomerDeliveryStats() async {
    return await get('/api/customer/stats/delivery-performance');
  }

  Future<void> updateLocation(String tripId, double latitude, double longitude) async {
    await post('/api/trips/$tripId/location', body: {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getLocationHistory(String tripId) async {
    final response = await get('/api/trips/$tripId/locations');
    return List<Map<String, dynamic>>.from(response['locations'] ?? response['data'] ?? []);
  }
}