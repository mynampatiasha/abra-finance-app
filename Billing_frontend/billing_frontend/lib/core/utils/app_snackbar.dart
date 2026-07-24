import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';

class AppSnackbar {
  /// Shows a top-centered notification banner globally.
  ///
  /// Automatically uses `overlay_support` so it slides from the top
  /// regardless of keyboard state or Scaffold positioning.
  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
  }) {
    showSimpleNotification(
      Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      background: isError ? Colors.red.shade600 : const Color(0xFF1A3A6B),
      position: NotificationPosition.top,
      elevation: 4,
      slideDismissDirection: DismissDirection.up,
      duration: const Duration(seconds: 3),
    );
  }
}
