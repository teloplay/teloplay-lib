import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/core/logging/app_logger.dart';
import '/core/theme/app_theme_extension.dart';

/// Must be called once from main.dart before runApp().
/// Handles two types of errors:
/// 1. Flutter framework error (during widget build) — caught via
///    FlutterError.onError, logged to AppLogger.
/// 2. Dart errors outside Flutter (async/isolate-level uncaught) —
///    caught via PlatformDispatcher.instance.onError.
///
/// Also replaces the default red/yellow "Error" screen in debug builds
/// with a friendly error widget (release builds never show raw errors).
class ErrorHandler {
  ErrorHandler._();

  static void init() {
    FlutterError.onError = (FlutterErrorDetails details) {
      AppLogger.error(
        'Flutter framework error: ${details.exceptionAsString()}',
        details.exception,
        details.stack,
      );
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppLogger.error('Uncaught async error', error, stack);
      return true;
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      if (kDebugMode) {
        return ErrorWidget(details.exception);
      }
      // Release build: user-friendly widget with AuroraColors fallback
      // (no BuildContext available at ErrorWidget.builder time).
      final aurora = AuroraColors.dark;
      return Material(
        color: aurora.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    color: aurora.error, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Something went wrong',
                  style: TextStyle(
                      color: aurora.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    };
  }
}