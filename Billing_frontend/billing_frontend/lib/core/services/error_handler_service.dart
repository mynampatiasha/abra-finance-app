// lib/core/services/error_handler_service.dart
// ============================================================================
// 🔇 SILENT ERROR HANDLER - NEVER BLOCKS UI WITH DIALOGS
// ============================================================================
// All errors are logged to console only. No dialogs, no snackbars, no blocking.
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';

enum ErrorSeverity {
  low,      // Log only
  medium,   // Log only
  high,     // Log only
  critical, // Log only
}

class ErrorInfo {
  final String userMessage;
  final String technicalMessage;
  final ErrorSeverity severity;
  final String? actionHint;
  final VoidCallback? retryAction;

  const ErrorInfo({
    required this.userMessage,
    required this.technicalMessage,
    required this.severity,
    this.actionHint,
    this.retryAction,
  });
}

class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  // ✅ CIRCUIT BREAKER STATE
  int _consecutiveFailures = 0;
  DateTime? _lastFailureTime;
  bool _circuitBreakerOpen = false;
  
  // ✅ CONFIGURATION
  static const int _maxConsecutiveFailures = 5;
  static const Duration _circuitBreakerTimeout = Duration(minutes: 2);
  
  // ✅ CHECK IF CIRCUIT BREAKER ALLOWS REQUESTS
  bool get canMakeRequest {
    if (!_circuitBreakerOpen) return true;
    
    // Check if timeout has passed
    if (_lastFailureTime != null) {
      final timeSinceLastFailure = DateTime.now().difference(_lastFailureTime!);
      if (timeSinceLastFailure > _circuitBreakerTimeout) {
        debugPrint('🔄 Circuit breaker timeout passed, resetting...');
        _resetCircuitBreaker();
        return true;
      }
    }
    
    return false;
  }

  // ✅ CIRCUIT BREAKER STATUS
  bool get isCircuitBreakerOpen => _circuitBreakerOpen;
  int get failureCount => _consecutiveFailures;
  Duration? get timeUntilReset {
    if (!_circuitBreakerOpen || _lastFailureTime == null) return null;
    final elapsed = DateTime.now().difference(_lastFailureTime!);
    final remaining = _circuitBreakerTimeout - elapsed;
    return remaining.isNegative ? null : remaining;
  }

  // ✅ RECORD SUCCESSFUL API CALL
  void recordSuccess() {
    if (_consecutiveFailures > 0 || _circuitBreakerOpen) {
      debugPrint('✅ API call succeeded, resetting circuit breaker');
      _resetCircuitBreaker();
    }
  }

  // ✅ RECORD FAILED API CALL
  void recordFailure() {
    _consecutiveFailures++;
    _lastFailureTime = DateTime.now();
    
    if (_consecutiveFailures >= _maxConsecutiveFailures && !_circuitBreakerOpen) {
      _circuitBreakerOpen = true;
      debugPrint('⛔ CIRCUIT BREAKER OPENED after $_consecutiveFailures failures');
      debugPrint('⏰ Will retry after ${_circuitBreakerTimeout.inMinutes} minutes');
    } else {
      debugPrint('⚠️ Failure count: $_consecutiveFailures/$_maxConsecutiveFailures');
    }
  }

  // ✅ RESET CIRCUIT BREAKER
  void _resetCircuitBreaker() {
    _consecutiveFailures = 0;
    _circuitBreakerOpen = false;
    _lastFailureTime = null;
  }

  // ✅ MANUAL RESET (for user-triggered retry)
  void manualReset() {
    debugPrint('🔄 Manual circuit breaker reset');
    _resetCircuitBreaker();
  }

  /// Processes any error and returns appropriate user-facing information
  ErrorInfo processError(dynamic error, {String? context}) {
    // ✅ Record failure for circuit breaker
    recordFailure();

    // Handle ApiException specifically
    if (error is ApiException) {
      return _handleApiException(error, context);
    }

    // Handle other exception types
    final errorString = error.toString();
    
    // Network connectivity issues
    if (_isNetworkError(errorString)) {
      return ErrorInfo(
        userMessage: 'Connection issue detected',
        technicalMessage: errorString,
        severity: ErrorSeverity.low,
        actionHint: 'The service will retry automatically',
      );
    }

    // Authentication errors
    if (_isAuthError(errorString)) {
      return ErrorInfo(
        userMessage: 'Authentication required',
        technicalMessage: errorString,
        severity: ErrorSeverity.low,
        actionHint: 'Please log in again',
      );
    }

    // Generic error
    return ErrorInfo(
      userMessage: 'Something went wrong',
      technicalMessage: errorString,
      severity: ErrorSeverity.low,
      actionHint: 'The service will retry automatically',
    );
  }

  ErrorInfo _handleApiException(ApiException apiException, String? context) {
    final statusCode = apiException.statusCode;
    final message = apiException.message;

    // Network/Connection errors (no status code)
    if (statusCode == null) {
      if (_isNetworkError(message)) {
        return ErrorInfo(
          userMessage: 'Unable to connect to server',
          technicalMessage: message,
          severity: ErrorSeverity.low,
          actionHint: 'The service will retry automatically',
        );
      }
    }

    // HTTP status code based handling
    switch (statusCode) {
      case 400:
        return ErrorInfo(
          userMessage: 'Invalid request',
          technicalMessage: message,
          severity: ErrorSeverity.low,
          actionHint: 'Please check your input and try again',
        );
      
      case 401:
        return ErrorInfo(
          userMessage: 'Authentication required',
          technicalMessage: message,
          severity: ErrorSeverity.low,
          actionHint: 'Please log in again',
        );
      
      case 403:
        return ErrorInfo(
          userMessage: 'Access denied',
          technicalMessage: message,
          severity: ErrorSeverity.low,
          actionHint: 'You don\'t have permission for this action',
        );
      
      case 404:
        return ErrorInfo(
          userMessage: 'Resource not found',
          technicalMessage: message,
          severity: ErrorSeverity.low,
          actionHint: 'The requested item may have been removed',
        );
      
      case 500:
      case 502:
      case 503:
      case 504:
        return ErrorInfo(
          userMessage: 'Server temporarily unavailable',
          technicalMessage: message,
          severity: ErrorSeverity.low,
          actionHint: 'The service will retry automatically',
        );
      
      default:
        return ErrorInfo(
          userMessage: 'Service temporarily unavailable',
          technicalMessage: message,
          severity: ErrorSeverity.low,
          actionHint: 'The service will retry automatically',
        );
    }
  }

  bool _isNetworkError(String errorMessage) {
    final networkKeywords = [
      'network error',
      'connection refused',
      'connection reset',
      'timeout',
      'unreachable',
      'no internet',
      'socket exception',
      'client exception',
      'handshake exception',
      'failed host lookup',
      'os error',
    ];
    
    final lowerMessage = errorMessage.toLowerCase();
    return networkKeywords.any((keyword) => lowerMessage.contains(keyword));
  }

  bool _isAuthError(String errorMessage) {
    final authKeywords = [
      'unauthorized',
      'authentication',
      'invalid token',
      'token expired',
      'access denied',
      'forbidden',
    ];
    
    final lowerMessage = errorMessage.toLowerCase();
    return authKeywords.any((keyword) => lowerMessage.contains(keyword));
  }

  /// ✅ NEVER SHOW ANY UI - ONLY LOG TO CONSOLE
  void showErrorToUser(BuildContext context, ErrorInfo errorInfo) {
    // ✅ COMPLETELY SILENT - NO UI DISPLAY
    _logErrorToConsole(errorInfo);
  }

  void _logErrorToConsole(ErrorInfo errorInfo) {
    final icon = _getSeverityIcon(errorInfo.severity);
    debugPrint('$icon [${errorInfo.severity.name.toUpperCase()}] ${errorInfo.userMessage}');
    if (kDebugMode) {
      debugPrint('   Technical: ${errorInfo.technicalMessage}');
      if (errorInfo.actionHint != null) {
        debugPrint('   Hint: ${errorInfo.actionHint}');
      }
    }
  }

  String _getSeverityIcon(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return '🔇';
      case ErrorSeverity.medium:
        return '⚠️';
      case ErrorSeverity.high:
        return '🚨';
      case ErrorSeverity.critical:
        return '💥';
    }
  }

  /// Handles errors silently for background operations
  void handleSilentError(dynamic error, {String? context}) {
    final errorInfo = processError(error, context: context);
    _logErrorToConsole(errorInfo);
  }

  /// ✅ HANDLES ALL ERRORS SILENTLY - NO UI DISPLAY
  void handleError(BuildContext context, dynamic error, {String? errorContext}) {
    final errorInfo = processError(error, context: errorContext);
    _logErrorToConsole(errorInfo);
  }
}

/// Extension to make error handling easier
extension ErrorHandling on Widget {
  /// Wraps a widget with error boundary
  Widget withErrorBoundary({String? context}) {
    return Builder(
      builder: (BuildContext context) {
        return this;
      },
    );
  }
}

/// ✅ GLOBAL HELPER: Show error in console only
void showErrorInConsoleOnly(String message, {String? context, dynamic error}) {
  debugPrint('🔇 [${context ?? 'Error'}] $message');
  if (error != null && kDebugMode) {
    debugPrint('   Details: $error');
  }
}

/// Mixin for easy error handling in StatefulWidgets
mixin ErrorHandlerMixin<T extends StatefulWidget> on State<T> {
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  void handleError(dynamic error, {String? context}) {
    if (mounted) {
      _errorHandler.handleError(this.context, error, errorContext: context);
    }
  }

  void handleSilentError(dynamic error, {String? context}) {
    _errorHandler.handleSilentError(error, context: context);
  }

  bool get canMakeRequest => _errorHandler.canMakeRequest;
  void recordSuccess() => _errorHandler.recordSuccess();
  bool get isCircuitBreakerOpen => _errorHandler.isCircuitBreakerOpen;
  void resetCircuitBreaker() => _errorHandler.manualReset();
}