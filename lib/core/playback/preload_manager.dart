import 'dart:async';

import '../logging/app_logger.dart';
import '../../services/performance_service.dart';
import 'playback_engine.dart';

// ⚠️ Adaptive Buffering (Phase 1) — Predictive Preload
// ═══════════════════════════════════════════════════════════════
//
// Roadmap constraint: এই abstraction Phase 3 Smart Cache-এর
// reuse-যোগ্যতা মাথায় রেখে ডিজাইন করা — "stream-URL ও future
// audio-bytes উভয়ের জন্য কাজ করবে এমন shape"।
//
// এখানে সেই reuse-যোগ্যতা কীভাবে রাখা হয়েছে:
//   - `_PreloadSlot<T>` generic — Phase 1-এ T = ResolvedStream (শুধু
//     URL + metadata), Phase 3-এ Smart Cache চাইলে T = CachedAudioBytes
//     (বা similar) নিয়ে এই একই slot/token/race-protection pattern
//     পুনর্ব্যবহার করতে পারবে, শুধু resolver function বদলে দিলেই হবে।
//   - Resolver injection (`Future<T> Function(String videoId)`) —
//     PreloadManager নিজে জানে না resolve *কীভাবে* হয় (engine call
//     নাকি future audio-byte download), শুধু "একটা future-producing
//     function কল করো, ফলাফল cache slot-এ রাখো" — Phase 3-এ এই একই
//     manager class audio-download resolver দিয়ে reuse করা যাবে,
//     rewrite লাগবে না।
//   - Single-slot (শুধু next ১টা track) — Phase 1 roadmap-এ explicit:
//     "শুধু next 1 track preload (Phase 1), Multiple track preload
//     এখন না (Phase 3 Smart Cache)"। তাই এখানে ইচ্ছাকৃতভাবে map/list
//     bানানো হয়নি — Phase 3-এ multi-slot দরকার হলে `Map<String, _Slot>`
//     এ upgrade করা straightforward হবে (single-slot logic-ই বেস)।
//
// Race-condition handling MusicPlayerRepository-এর `_playRequestToken`
// pattern-এর সাথেই সঙ্গতিপূর্ণ রাখা হয়েছে (monotonic token, stale
// result silently discard) — একই কোডবেসে দুই রকম race-guard pattern
// না রেখে consistency বজায় রাখতে।
//
// ⚠️ Phase 1 (Smart Performance Foundation) — Background Task
// Throttling। Preload একটা pure "nice to have" optimization (পরের
// track দ্রুত শুরু হওয়া), playback correctness এর উপর নির্ভর করে না
// (না হলে normal resolve path কাজ করবেই)। তাই app background-এ থাকলে
// (user screen দেখছেই না, তাই "instant next-track" experience-এর কোনো
// মূল্য নেই এই মুহূর্তে) বা device ইতিমধ্যে memory-pressure-এ থাকলে
// (Low RAM mode) এই network/CPU কাজটা skip করাই স্বাভাবিক —
// `PerformanceService.runThrottled()` ঠিক এই policy-টাই কেন্দ্রীভূত
// রাখে, এখানে আলাদা কোনো if-check বসাতে হয়নি।
class PreloadManager<T> {
  final Future<T> Function(String videoId) _resolver;

  PreloadManager(this._resolver);

  String? _preloadedVideoId;
  T? _preloadedStream;
  Future<T>? _inFlightPreload;
  int _preloadToken = 0;

  /// এই videoId-এর জন্য preload আগে থেকেই সম্পন্ন/চলমান আছে কিনা।
  bool isPreloadedOrPending(String videoId) =>
      _preloadedVideoId == videoId || _inFlightPreload != null;

  /// Background-এ next track resolve শুরু করা — fire-and-forget,
  /// exception swallow করা হয় (preload ব্যর্থ হলেও এখন track playback
  /// প্রভাবিত হওয়া উচিত না, শুধু পরে "instant" না হয়ে normal resolve
  /// হবে — non-critical enhancement, ঠিক searchSuggestions()-এর মতোই
  /// non-throwing contract)।
  ///
  /// ⚠️ App background বা Low RAM mode-এ এই পুরো কাজটাই skip হয়ে যায়
  /// (দেখো class-level নোট) — `runThrottled()` fire-and-forget হওয়ায়
  /// `preload()`-এর নিজের sync/void signature অপরিবর্তিত থাকে, caller-side
  /// (MusicPlayerRepository) কোনো change লাগে না।
  void preload(String videoId) {
    if (_preloadedVideoId == videoId) return; // আগেই preloaded
    if (_inFlightPreload != null) return; // ইতিমধ্যে অন্য একটা চলছে

    unawaited(PerformanceService.instance.runThrottled(
      'preload-next-track:$videoId',
      () => _startPreload(videoId),
    ));
  }

  Future<void> _startPreload(String videoId) async {
    // ⚠️ runThrottled()-এর await-এর মধ্যে সময় গ্যাপে (নেই বললেই চলে,
    // কিন্তু নিরাপদে) videoId ইতিমধ্যে preloaded/in-flight হয়ে যায়নি তো,
    // সেটা আবার চেক করা হচ্ছে — defensive, race harmless কিন্তু duplicate
    // network call এড়াতে সস্তা গার্ড।
    if (_preloadedVideoId == videoId || _inFlightPreload != null) return;

    final myToken = ++_preloadToken;
    AppLogger.playback('[preload] starting for videoId=$videoId');

    final future = _resolver(videoId);
    _inFlightPreload = future;

    try {
      final resolved = await future;
      if (myToken != _preloadToken) {
        // এর মধ্যে নতুন preload/track-change হয়ে গেছে — stale result
        // discard।
        AppLogger.playback('[preload] stale result discarded: $videoId');
        return;
      }
      _preloadedVideoId = videoId;
      _preloadedStream = resolved;
      _inFlightPreload = null;
      AppLogger.playback('[preload] ready: $videoId');
    } catch (e) {
      if (myToken != _preloadToken) return;
      AppLogger.playback(
        '[preload] failed (non-critical), will resolve normally later: $videoId — $e',
      );
      _inFlightPreload = null;
    }
  }

  /// Preload হওয়া stream থাকলে সেটা নিয়ে নেওয়া (এবং slot খালি করা) —
  /// পাওয়া না গেলে null, caller তখন normal `_resolveWithRetry()` পথে
  /// যাবে। এটা consume করলে slot খালি হয়ে যায় যাতে stale data পরের
  /// track-এ ভুলভাবে reuse না হয়।
  T? takeIfMatches(String videoId) {
    if (_preloadedVideoId == videoId && _preloadedStream != null) {
      final stream = _preloadedStream;
      _clear();
      return stream;
    }
    return null;
  }

  /// নতুন track শুরু হওয়ার সময় বা track বদলানোর সময় কল করা উচিত, যাতে
  /// stale preload slot পরবর্তী ভুল track-এর জন্য ব্যবহার না হয় এবং
  /// in-flight preload (যদি অন্য track-এর জন্য চলছিল) result token
  /// mismatch-এর কারণে silently discard হয়ে যায়।
  void _clear() {
    _preloadedVideoId = null;
    _preloadedStream = null;
  }

  void invalidate() {
    _preloadToken++; // in-flight থাকলে সেটার result এখন stale গণ্য হবে
    _clear();
    _inFlightPreload = null;
  }
}