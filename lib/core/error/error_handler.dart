import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../logging/app_logger.dart';

/// App শুরুতে main.dart থেকে একবার call করতে হবে (runApp-এর আগে)।
/// দুই ধরনের error handle করে:
/// 1. Flutter framework error (widget build-এর সময় exception) —
///    FlutterError.onError দিয়ে ধরা হয়, AppLogger-এ log হয়।
/// 2. Flutter-এর বাইরের Dart error (async/isolate-level uncaught exception)
///    — PlatformDispatcher.instance.onError দিয়ে ধরা হয়।
///
/// এছাড়া debug build-এ লাল/হলুদ ডিফল্ট "Error" স্ক্রিনের বদলে একটা
/// friendly error widget দেখানো হয় (release build-এ ব্যবহারকারী কখনো
/// raw error দেখবে না)।
class ErrorHandler {
  ErrorHandler._();

  static void init() {
    FlutterError.onError = (FlutterErrorDetails details) {
      AppLogger.error(
        'Flutter framework error: ${details.exceptionAsString()}',
        details.exception,
        details.stack,
      );
      // Debug console-এও দেখানো হোক (Flutter-এর নিজের default behavior)
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppLogger.error('Uncaught async error', error, stack);
      return true; // true মানে error handled, app crash করবে না
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      if (kDebugMode) {
        // Debug-এ পুরো error details দেখা দরকার, ডিফল্ট red screen-ই রাখা হলো
        return ErrorWidget(details.exception);
      }
      // Release build-এ user-friendly widget
      return Material(
        color: const Color(0xFF121212),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                SizedBox(height: 12),
                Text(
                  'কিছু একটা ভুল হয়েছে',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
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