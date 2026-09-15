import 'dart:async';
import 'dart:math';

import '../../core/logging/app_logger.dart';

/// Phase 4 — Exponential Backoff & Retry Manager for failed sync queue items.
class RetryManager {
  static const int maxRetries = 5;
  static const Duration baseDelay = Duration(seconds: 2);

  /// Calculates delay before next retry based on retry count.
  Duration calculateDelay(int retryCount) {
    if (retryCount >= maxRetries) return Duration.zero;
    final exponent = pow(2, retryCount).toInt();
    final delaySeconds = baseDelay.inSeconds * exponent;
    // Cap delay at 5 minutes
    final capped = min(delaySeconds, 300);
    return Duration(seconds: capped);
  }

  /// Determines if task has exceeded maximum retry limit.
  bool isMaxRetriesExceeded(int retryCount) {
    return retryCount >= maxRetries;
  }

  /// Executes an operation with automatic retry on error.
  Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    required String taskName,
    int maxAttempts = 3,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        attempt++;
        return await operation();
      } catch (e) {
        if (attempt >= maxAttempts) {
          AppLogger.sync('Task "$taskName" failed after $maxAttempts attempts: $e');
          rethrow;
        }
        final delay = calculateDelay(attempt);
        AppLogger.sync('Task "$taskName" failed (attempt $attempt), retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }
    }
  }
}
