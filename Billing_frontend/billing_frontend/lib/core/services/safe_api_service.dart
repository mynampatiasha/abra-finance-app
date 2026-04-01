// lib/core/services/safe_api_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'error_handler_service.dart';

/// A wrapper around ApiService that handles errors gracefully
/// and provides fallback data when the backend is unavailable
class SafeApiService {
  static final SafeApiService _instance = SafeApiService._internal();
  factory SafeApiService() => _instance;
  SafeApiService._internal();

  final ApiService _apiService = ApiService();
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  /// Cache for storing last successful responses
  final Map<String, dynamic> _responseCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  /// Maximum cache age in minutes
  static const int _maxCacheAgeMinutes = 5;

  // ✅ ADD: Check if requests are allowed
  bool get canMakeRequest => _errorHandler.canMakeRequest;

  /// Safely executes an API call with error handling and caching
  Future<T> safeCall<T>(
    Future<T> Function() apiCall,
    T fallbackValue, {
    String? cacheKey,
    String? context,
    bool useCache = true,
  }) async {
    // ✅ CHECK CIRCUIT BREAKER FIRST
    if (!_errorHandler.canMakeRequest) {
      debugPrint('⛔ Circuit breaker open, skipping API call: $context');
      
      // Try to return cached data
      if (cacheKey != null && useCache && _responseCache.containsKey(cacheKey)) {
        debugPrint('🔄 Returning cached data (circuit breaker open): $cacheKey');
        return _responseCache[cacheKey] as T;
      }
      
      // Return fallback
      return fallbackValue;
    }

    try {
      // Try the API call
      final result = await apiCall();
      
      // ✅ RECORD SUCCESS
      _errorHandler.recordSuccess();
      
      // Cache successful result if cache key provided
      if (cacheKey != null && useCache) {
        _responseCache[cacheKey] = result;
        _cacheTimestamps[cacheKey] = DateTime.now();
      }
      
      return result;
    } catch (error) {
      // ✅ Handle the error silently
      _errorHandler.handleSilentError(error, context: context);
      
      // Try to return cached data if available and not too old
      if (cacheKey != null && useCache && _responseCache.containsKey(cacheKey)) {
        final cacheTime = _cacheTimestamps[cacheKey];
        if (cacheTime != null) {
          final age = DateTime.now().difference(cacheTime).inMinutes;
          if (age <= _maxCacheAgeMinutes) {
            debugPrint('🔄 Returning cached data for $cacheKey (age: ${age}m)');
            return _responseCache[cacheKey] as T;
          } else {
            debugPrint('⚠️ Cache expired for $cacheKey (age: ${age}m)');
          }
        }
      }
      
      // Return fallback value
      debugPrint('🔄 Returning fallback value for $context');
      return fallbackValue;
    }
  }

  /// Safely get data with automatic fallback
  Future<Map<String, dynamic>> safeGet(
    String endpoint, {
    Map<String, String>? queryParams,
    String? context,
    Map<String, dynamic>? fallback,
  }) async {
    return safeCall(
      () => _apiService.get(endpoint, queryParams: queryParams),
      fallback ?? {'success': false, 'offline': true},
      cacheKey: endpoint,
      context: context ?? 'GET $endpoint',
    );
  }

  /// Safely post data with error handling
  Future<Map<String, dynamic>> safePost(
    String endpoint, {
    Map<String, dynamic>? body,
    String? context,
    Map<String, dynamic>? fallback,
  }) async {
    return safeCall(
      () => _apiService.post(endpoint, body: body),
      fallback ?? {'success': false, 'offline': true},
      cacheKey: null, // Don't cache POST requests
      context: context ?? 'POST $endpoint',
      useCache: false,
    );
  }

  /// Safely put data with error handling
  Future<Map<String, dynamic>> safePut(
    String endpoint, {
    Map<String, dynamic>? body,
    String? context,
    Map<String, dynamic>? fallback,
  }) async {
    return safeCall(
      () => _apiService.put(endpoint, body: body),
      fallback ?? {'success': false, 'offline': true},
      cacheKey: null, // Don't cache PUT requests
      context: context ?? 'PUT $endpoint',
      useCache: false,
    );
  }

  /// Safely patch data with error handling
  Future<Map<String, dynamic>> safePatch(
    String endpoint, {
    Map<String, dynamic>? body,
    String? context,
    Map<String, dynamic>? fallback,
  }) async {
    return safeCall(
      () => _apiService.patch(endpoint, body: body),
      fallback ?? {'success': false, 'offline': true},
      cacheKey: null, // Don't cache PATCH requests
      context: context ?? 'PATCH $endpoint',
      useCache: false,
    );
  }

  /// Safely delete data with error handling
  Future<Map<String, dynamic>> safeDelete(
    String endpoint, {
    String? context,
    Map<String, dynamic>? fallback,
  }) async {
    return safeCall(
      () => _apiService.delete(endpoint),
      fallback ?? {'success': false, 'offline': true},
      cacheKey: null, // Don't cache DELETE requests
      context: context ?? 'DELETE $endpoint',
      useCache: false,
    );
  }

  /// Get vehicles with fallback data
  Future<List<Map<String, dynamic>>> getVehiclesSafe() async {
    return safeCall(
      () => _apiService.getVehicles(),
      <Map<String, dynamic>>[], // Empty list as fallback
      cacheKey: 'vehicles',
      context: 'Get Vehicles',
    );
  }

  /// Get drivers with fallback data
  Future<List<Map<String, dynamic>>> getDriversSafe() async {
    return safeCall(
      () => _apiService.getDrivers(),
      <Map<String, dynamic>>[], // Empty list as fallback
      cacheKey: 'drivers',
      context: 'Get Drivers',
    );
  }

  /// Get trips with fallback data
  Future<List<Map<String, dynamic>>> getTripsSafe() async {
    return safeCall(
      () => _apiService.getTrips(),
      <Map<String, dynamic>>[], // Empty list as fallback
      cacheKey: 'trips',
      context: 'Get Trips',
    );
  }

  /// Check if service is online
  Future<bool> isOnline() async {
    try {
      await _apiService.checkHealth();
      _errorHandler.recordSuccess(); // ✅ Record success
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear all cached data
  void clearCache() {
    _responseCache.clear();
    _cacheTimestamps.clear();
    debugPrint('🗑️ API cache cleared');
  }

  /// Get cache status for debugging
  Map<String, dynamic> getCacheStatus() {
    final now = DateTime.now();
    final status = <String, dynamic>{};
    
    for (final key in _responseCache.keys) {
      final timestamp = _cacheTimestamps[key];
      if (timestamp != null) {
        final age = now.difference(timestamp).inMinutes;
        status[key] = {
          'age_minutes': age,
          'is_valid': age <= _maxCacheAgeMinutes,
          'cached_at': timestamp.toIso8601String(),
        };
      }
    }
    
    return status;
  }

  /// Preload critical data
  Future<void> preloadCriticalData() async {
    debugPrint('🔄 Preloading critical data...');
    
    // Run all critical API calls in parallel
    await Future.wait([
      getVehiclesSafe(),
      getDriversSafe(),
      getTripsSafe(),
    ]);
    
    debugPrint('✅ Critical data preload completed');
  }
}

/// Extension for easy safe API usage
extension SafeApiExtension on ApiService {
  SafeApiService get safe => SafeApiService();
}