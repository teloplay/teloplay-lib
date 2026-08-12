import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// পুরো app-এ এই একটাই Logger ব্যবহার হবে — কোথাও সরাসরি print() না।
/// Release build-এ verbosity কমিয়ে দেওয়া হয় (শুধু warning/error দেখাবে),
/// debug build-এ সব দেখাবে (Smart Playback Engine debug করার সময় এটা
/// কাজে লাগবে — buffer underrun, stream switch time ইত্যাদি log করতে)।
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: kDebugMode ? 1 : 0,
      errorMethodCount: 5,
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: kDebugMode ? Level.debug : Level.warning,
  );

  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Playback engine-এর জন্য আলাদা shorthand — Phase 1 (Smart Playback
  /// Engine)-এ stream selection, buffering, preload ইত্যাদির log সহজে
  /// আলাদা করে চেনার জন্য একটা consistent prefix ব্যবহার করা হয়েছে।
  static void playback(String message) {
    _logger.d('🎵 [Playback] $message');
  }

  /// ⚠️ Phase 1 (Smart Performance Foundation) — PerformanceService-এর
  /// RSS sampling, low-RAM mode transition, throttled-task skip ইত্যাদি
  /// এই shorthand দিয়ে log হয়। আলাদা prefix রাখা হয়েছে যাতে debug console-এ
  /// playback log-এর সাথে মিশে না যায় — performance metrics সাধারণত
  /// অনেক বেশি frequent (periodic polling), আলাদা করে চেনা/filter করা
  /// দরকার হতে পারে।
  ///
  /// `debug` level ব্যবহার করা হচ্ছে (info/warning না) — এগুলো routine
  /// telemetry, কোনো actionable সংকেত না বেশিরভাগ সময়, তাই release
  /// build-এ (level: warning) এমনিতেই silent থাকবে।
  static void performance(String message) {
    _logger.d('⚡ [Perf] $message');
  }

  /// ⚠️ v11 Fix (stabilization) — Metadata cache (L2, Deezer/Last.fm/
  /// MusicBrainz/YouTube) hit/miss/expiry log. This shorthand was already
  /// called from metadata_cache_service.dart but never defined here —
  /// added to match the existing playback/performance pattern rather than
  /// stripping the call sites.
  static void cache(String message) {
    _logger.d('💾 [Cache] $message');
  }

  /// ⚠️ v11 Fix — Discovery queue (Last.fm/MusicBrainz background
  /// enrichment, rate-limited batch processing) log.
  static void discovery(String message) {
    _logger.d('🔭 [Discovery] $message');
  }

  /// ⚠️ v11 Fix — Search orchestrator (parallel YouTube+Deezer fetch,
  /// stream matching) log.
  static void search(String message) {
    _logger.d('🔍 [Search] $message');
  }

  /// ⚠️ v11 Fix — Continue Session (multi-song resume save/restore) log.
  static void session(String message) {
    _logger.d('▶️ [Session] $message');
  }

  /// ⚠️ v11 Fix — Drift schema migration log (schema bump / safe column
  /// add / table create skip-on-already-exists). Was called from
  /// database.dart's migration helpers but never defined.
  static void drift(String message) {
    _logger.d('🗄️ [Drift] $message');
  }
}
