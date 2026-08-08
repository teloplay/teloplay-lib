import 'dart:async';
import 'dart:io' show ProcessInfo, Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState, PaintingBinding;

import '../core/logging/app_logger.dart';

/// ⚠️ Phase 1 (Smart Performance Foundation) — এটা কোনো একটা Phase-এ
/// "শেষ" হওয়ার মতো ফিচার না (roadmap-এর নিজস্ব নীতি অনুযায়ী), বরং
/// একটা lightweight, সবসময়-চলমান singleton service যেটা:
///
///   1. Low RAM detection — app startup-এ device-এর available RAM
///      একবার sample করে একটা coarse tier (`isLowRamMode`) সেট করে।
///      অন্য সব service (CachedArtwork, ভবিষ্যতে Smart Cache) এই flag
///      পড়ে decode/cache decision নেয়।
///   2. Memory cleanup — app background-এ গেলে (`AppLifecycleState.paused`)
///      Flutter-এর image cache aggressively clear করা হয় (foreground-এ
///      user দেখছে না এমন bitmap RAM-এ রাখার দরকার নেই)।
///   3. Background task throttling — সাধারণ non-critical periodic/
///      idle-time কাজ (যেমন future cache-cleanup sweep) এই service-এর
///      `runThrottled()`-এর মাধ্যমে চালানো উচিত, যাতে app background-এ
///      বা low-RAM অবস্থায় সেগুলো স্বয়ংক্রিয়ভাবে স্কিপ/delay হয়।
///   4. Performance metrics logging — RSS-এর পাশাপাশি একটা আলাদা,
///      কম-ঘন-ঘন (120s) timer image-cache size/count-এর summary log করে
///      (debug build-only, `kDebugMode` গার্ড) — `AppLogger.performance()`
///      shorthand ব্যবহার করে।
///
/// এই service কোনো heavy platform-specific package (device_info_plus
/// ইত্যাদি) ব্যবহার করে না — ইচ্ছাকৃতভাবে, কারণ Dart VM নিজেই
/// `ProcessInfo.currentRss`/`maxRss` (dart:io) এক্সপোজ করে, যেটা এই
/// coarse tier-ভিত্তিক সিদ্ধান্তের জন্য যথেষ্ট। নতুন dependency এড়ানো
/// হয়েছে যেখানে standard library দিয়েই কাজ চলে।
class PerformanceService with WidgetsBindingObserver {
  PerformanceService._();
  static final PerformanceService instance = PerformanceService._();

  bool _initialized = false;

  // ═══════════════════════════════════════════════════════════════
  // Low RAM Mode
  // ═══════════════════════════════════════════════════════════════

  bool _isLowRamMode = false;
  bool get isLowRamMode => _isLowRamMode;
  // ⚠️ Phase 6 (Performance-aware UI) — placeholder getters only.
  // No settings UI, no persistence, no actual detection logic yet —
  // just the abstraction surface so transition/animation code can
  // depend on these names now. Wiring real toggles later only
  // changes what's inside these getters; every call site (page
  // transitions, Hero morphs, mini-player/artwork animation, glow/
  // blur intensity) stays untouched.
  bool get isReduceMotionEnabled => false;
  bool get isBatterySaverUiMode => false;

  final _lowRamModeController = StreamController<bool>.broadcast();
  Stream<bool> get lowRamModeStream => _lowRamModeController.stream;

  // ⚠️ Threshold নির্বাচন — `ProcessInfo.maxRss` হলো এই Dart/Flutter
  // process নিজে এ পর্যন্ত সর্বোচ্চ যা RAM ব্যবহার করেছে (device-এর
  // *total* RAM না, কারণ Dart VM সরাসরি total physical RAM জানার কোনো
  // platform-agnostic API এক্সপোজ করে না)। তাই এটা "device কম RAM-এর"
  // সরাসরি proxy না, বরং "এই app session-এ ইতিমধ্যে যথেষ্ট মেমরি চাপ
  // পড়েছে" তার signal — যেটা আসলে আমাদের দরকার: প্রি-এম্পটিভ device-tier
  // ক্যাটাগরাইজেশনের বদলে reactive throttling, কারণ এটা false-positive
  // (flagship device ভুলবশত low-RAM ধরা) এড়ায় এবং শুধুই বাস্তবে চাপ
  // পড়লে সাড়া দেয়।
  //
  // ⚠️ Fix (Windows debug-build false-positive) — আগে একটা একক 300MB
  // constant ছিল, যেটা Android-এর জন্য reasonable কিন্তু Windows debug
  // build-এ (Flutter engine + hot-reload overhead) সহজেই false-positive
  // trigger করত, cache/preload silently সবসময় skip হয়ে যেত।
  //
  // এখন platform-aware: Windows/Linux/macOS (desktop, সাধারণত অনেক বেশি
  // physical RAM + debug overhead ধরে রাখতে হয়) 1200MB, Android/iOS
  // (mobile, প্রকৃত memory-pressure সংকেত বেশি গুরুত্বপূর্ণ) আগের মতোই
  // 300MB। `kDebugMode` অনুযায়ী আরও আলাদা করা হয়নি ইচ্ছাকৃতভাবে
  // (over-engineering এড়াতে) — desktop threshold-ই যথেষ্ট বেশি রাখা
  // হয়েছে যাতে debug overhead-এই মিথ্যা trigger না হয়।
  static int get _rssLowRamThresholdBytes {
    if (kIsWeb) return 300 * 1024 * 1024;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return 1200 * 1024 * 1024; // 1.2 GB — desktop
    }
    return 300 * 1024 * 1024; // 300 MB — mobile (Android/iOS), অপরিবর্তিত
  }

  Timer? _rssPollTimer;
  static const _rssPollInterval = Duration(seconds: 30);

  // ═══════════════════════════════════════════════════════════════
  // Performance Metrics Summary
  // ═══════════════════════════════════════════════════════════════

  // ⚠️ আলাদা, কম-ঘন-ঘন টাইমার (RSS poll-এর চেয়ে ৪গুণ কম বার) — RSS
  // sample নিজে lightweight (একটা native call), কিন্তু image-cache
  // introspection (`imageCache.currentSize`/`liveImageCount`) সামান্য
  // বেশি খরচ করে, তাই আলাদা করে কম frequency-তে রাখা হয়েছে। শুধু
  // debug build-এ চলে (kDebugMode গার্ড) — release-এ AppLogger.performance
  // এমনিতেই silent (level: warning), কিন্তু timer নিজেও spawn না করাই
  // পরিষ্কার (production-এ অকারণ periodic wake-up এড়াতে)।
  Timer? _metricsSummaryTimer;
  static const _metricsSummaryInterval = Duration(seconds: 120);

  // ═══════════════════════════════════════════════════════════════
  // Background Task Throttling
  // ═══════════════════════════════════════════════════════════════

  bool _isBackgrounded = false;

  /// একটা non-critical background কাজ চালানোর আগে এই wrapper দিয়ে
  /// চালানো উচিত — app background-এ থাকলে বা low-RAM mode active
  /// থাকলে কাজটা স্কিপ হয়ে যাবে (silently, exception না), অন্যথায়
  /// স্বাভাবিকভাবে চলবে।
  ///
  /// শুধু "nice to have" idle-time কাজের জন্য (cache sweep, prefetch,
  /// analytics flush ইত্যাদি) — কখনো playback-critical পাথে ব্যবহার
  /// করা উচিত না, কারণ silently skip হয়ে যেতে পারে।
  Future<void> runThrottled(
    String label,
    Future<void> Function() task,
  ) async {
    if (_isBackgrounded) {
      AppLogger.performance('throttled: "$label" skipped (app backgrounded)');
      return;
    }
    if (_isLowRamMode) {
      AppLogger.performance('throttled: "$label" skipped (low RAM mode)');
      return;
    }
    try {
      await task();
    } catch (e) {
      AppLogger.error('Throttled task "$label" failed', e);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════════

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    _sampleRss();
    _rssPollTimer = Timer.periodic(_rssPollInterval, (_) => _sampleRss());

    if (kDebugMode) {
      _logMetricsSummary();
      _metricsSummaryTimer =
          Timer.periodic(_metricsSummaryInterval, (_) => _logMetricsSummary());
    }

    AppLogger.performance('PerformanceService initialized');
  }

  // ⚠️ একটা সংক্ষিপ্ত, এক-লাইন snapshot — RSS-এর মতো state-changing না,
  // শুধু periodic visibility (debug console-এ চোখ বুলিয়ে দেখা যায় কোনো
  // leak/growth pattern আছে কিনা, যেমন `liveImageCount` অস্বাভাবিকভাবে
  // বাড়তে থাকা মানে image dispose ঠিকভাবে হচ্ছে না কোথাও)।
  void _logMetricsSummary() {
    try {
      final cache = PaintingBinding.instance.imageCache;
      AppLogger.performance(
        'summary: imageCache(count=${cache.currentSize}, '
        'liveImages=${cache.liveImageCount}, '
        'sizeBytes=${cache.currentSizeBytes}), '
        'lowRamMode=$_isLowRamMode, backgrounded=$_isBackgrounded',
      );
    } catch (e) {
      AppLogger.performance('metrics summary unavailable: $e');
    }
  }

  void _sampleRss() {
    if (kIsWeb) return; // ProcessInfo dart:io-only, web-এ প্রযোজ্য না
    try {
      final rss = ProcessInfo.currentRss;
      final wasLowRam = _isLowRamMode;
      _isLowRamMode = rss > _rssLowRamThresholdBytes;

      if (_isLowRamMode != wasLowRam) {
        _lowRamModeController.add(_isLowRamMode);
        AppLogger.performance(
          'Low RAM mode ${_isLowRamMode ? "ACTIVATED" : "deactivated"} '
          '(currentRss=${(rss / (1024 * 1024)).toStringAsFixed(1)}MB)',
        );
      } else {
        AppLogger.performance(
          'RSS sample: ${(rss / (1024 * 1024)).toStringAsFixed(1)}MB '
          '(lowRamMode=$_isLowRamMode)',
        );
      }
    } catch (e) {
      // কিছু platform (web, বা restricted sandbox)-এ ProcessInfo
      // unavailable হতে পারে — non-fatal, শুধু log করে এগিয়ে যাওয়া।
      AppLogger.performance('RSS sampling unavailable: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isBackgrounded = true;
        _onAppBackgrounded();
        break;
      case AppLifecycleState.resumed:
        _isBackgrounded = false;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // ⚠️ Memory cleanup — app background-এ গেলে Flutter-এর global
  // image cache clear করা হচ্ছে। এই মুহূর্তে user কোনো bitmap দেখছে না
  // (background playback audio-only চলতে থাকবে, কিন্তু UI paint হচ্ছে
  // না), তাই decoded image bitmap RAM-এ ধরে রাখার কোনো লাভ নেই —
  // ছেড়ে দিলে OS-এর কাছে app-কে kill না করার সম্ভাবনা বাড়ে (Android-এ
  // background audio session বাঁচিয়ে রাখতে এটা গুরুত্বপূর্ণ)।
  //
  // `PaintingBinding.instance.imageCache.clear()` শুধু in-memory decode
  // cache খালি করে — disk cache (cached_network_image-এর নিজস্ব, CachedArtwork
  // এর মাধ্যমে ব্যবহৃত) অক্ষত থাকে, তাই foreground-এ ফিরলে network hit
  // ছাড়াই দ্রুত আবার decode হবে (শুধু re-decode cost, re-download না)।
  void _onAppBackgrounded() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      AppLogger.performance('App backgrounded — in-memory image cache cleared');
    } catch (e) {
      AppLogger.error('Image cache clear on background failed', e);
    }
  }

  void dispose() {
    _rssPollTimer?.cancel();
    _metricsSummaryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_lowRamModeController.close());
    _initialized = false;
  }
}