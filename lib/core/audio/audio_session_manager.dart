import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../logging/app_logger.dart';
import '../playback/playback_engine.dart';

/// ⚠️ Bug fix (long-running background reliability) — root cause ছিল:
/// `AndroidPlaybackEngine` একবারই (app lifetime-এ একবার) `audio_session`-এর
/// event stream-গুলো (`interruptionEventStream`, `becomingNoisyEventStream`,
/// `devicesChangedEventStream`) subscribe করত, কোনো resubscribe/health-check
/// mechanism ছাড়াই। দীর্ঘ background সময়ে (Doze mode, Samsung battery
/// management, বা audio_service-এর নিজস্ব foreground-service lifecycle
/// event) platform channel-ভিত্তিক এই stream subscription silently মরে
/// যেতে পারে — subscription object নিজে valid থাকে (crash হয় না) কিন্তু
/// আর কোনো event আসে না। App-এর কোনো উপায় ছিল না এটা detect করার,
/// তাই symptom ছিল "মাঝে মাঝে কাজ করে, মাঝে মাঝে করে না, force-restart
/// করলে ঠিক হয়"।
///
/// Architecture (এই ফাইল একক owner):
///   AudioService (background lifecycle)
///        │
///   BaseAudioHandler (TeloPlayAudioHandler)
///        │
///   AudioSessionManager (এই ক্লাস) ← single owner, single configure()
///        │
///   MusicPlayerRepository (audioFocusStream শোনে)
///
/// দায়িত্ব:
///   - `audio_session` ঠিক একবার configure করা (কোনো caller একাধিকবার
///     configure/setActive কল করবে না — এটাই একমাত্র জায়গা)
///   - সব StreamSubscription এখানেই রাখা (owned references, GC-able না)
///   - `onDone`/`onError` হলে automatically resubscribe করা
///   - periodic health-check (heartbeat) দিয়ে "subscription silently
///     dead কিন্তু onDone/onError কখনো fire করেনি" এমন edge case-ও ধরা —
///     platform channel stream-এ onDone সবসময় guaranteed না, তাই শুধু
///     onDone/onError-নির্ভর recovery যথেষ্ট না
///   - Debug health metrics expose করা (last event timestamps, alive
///     status) যাতে ভবিষ্যতে একই ধরনের bug হলে দ্রুত ধরা যায়
class AudioSessionManager {
  final _audioFocusController = StreamController<AudioFocusSignal>.broadcast();
  Stream<AudioFocusSignal> get audioFocusStream => _audioFocusController.stream;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSub;

  AudioSession? _session;
  bool _configured = false;
  bool _disposed = false;

  Timer? _healthCheckTimer;
  static const _healthCheckInterval = Duration(minutes: 5);

  // ── Debug health metrics ──────────────────────────────────────────
  DateTime? _lastInterruptionEventAt;
  DateTime? _lastNoisyEventAt;
  DateTime? _lastDeviceChangeEventAt;
  DateTime? _lastResubscribeAt;
  int _resubscribeCount = 0;

  DateTime? get lastInterruptionEventAt => _lastInterruptionEventAt;
  DateTime? get lastNoisyEventAt => _lastNoisyEventAt;
  DateTime? get lastDeviceChangeEventAt => _lastDeviceChangeEventAt;
  DateTime? get lastResubscribeAt => _lastResubscribeAt;
  int get resubscribeCount => _resubscribeCount;

  bool get isSubscriptionAlive =>
      _interruptionSub != null &&
      !_interruptionSub!.isPaused &&
      _becomingNoisySub != null &&
      !_becomingNoisySub!.isPaused &&
      _devicesChangedSub != null &&
      !_devicesChangedSub!.isPaused;

  /// একবারই কল করতে হবে (app lifetime-এ) — `TeloPlayAudioHandler`
  /// থেকে, audio_service-এর background lifecycle-এর আওতায়। UI
  /// lifecycle (screen open/close, provider rebuild) থেকে স্বাধীন।
  Future<void> initialize() async {
    if (_configured) {
      AppLogger.playback('[AudioSessionManager] already configured, skip');
      return;
    }

    try {
      _session = await AudioSession.instance;
      // ⚠️ একমাত্র configure() কল — কোনো অন্য জায়গা থেকে (যেমন আগে
      // AndroidPlaybackEngine-এ ছিল) আর configure/setActive কল করা
      // হবে না। Single owner principle।
      await _session!.configure(const AudioSessionConfiguration.music());
      await _session!.setActive(true);
      _configured = true;

      _subscribeAll();
      _startHealthCheck();

      AppLogger.playback('[AudioSessionManager] configured & subscribed');
    } catch (e) {
      AppLogger.error('[AudioSessionManager] initialize failed', e);
    }
  }

  void _subscribeAll() {
    final session = _session;
    if (session == null || _disposed) return;

    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    _devicesChangedSub?.cancel();

    _interruptionSub = session.interruptionEventStream.listen(
      _onInterruptionEvent,
      onError: (Object e, StackTrace st) {
        AppLogger.error('[AudioSessionManager] interruptionStream error', e);
        _scheduleResubscribe(reason: 'interruptionStream error');
      },
      onDone: () {
        AppLogger.playback(
          '[AudioSessionManager] interruptionStream closed unexpectedly',
        );
        _scheduleResubscribe(reason: 'interruptionStream closed');
      },
    );

    _becomingNoisySub = session.becomingNoisyEventStream.listen(
      (_) => _onBecomingNoisy(),
      onError: (Object e, StackTrace st) {
        AppLogger.error('[AudioSessionManager] becomingNoisyStream error', e);
        _scheduleResubscribe(reason: 'becomingNoisyStream error');
      },
      onDone: () {
        AppLogger.playback(
          '[AudioSessionManager] becomingNoisyStream closed unexpectedly',
        );
        _scheduleResubscribe(reason: 'becomingNoisyStream closed');
      },
    );

    _devicesChangedSub = session.devicesChangedEventStream.listen(
      _onDevicesChanged,
      onError: (Object e, StackTrace st) {
        AppLogger.error('[AudioSessionManager] devicesChangedStream error', e);
        _scheduleResubscribe(reason: 'devicesChangedStream error');
      },
      onDone: () {
        AppLogger.playback(
          '[AudioSessionManager] devicesChangedStream closed unexpectedly',
        );
        _scheduleResubscribe(reason: 'devicesChangedStream closed');
      },
    );
  }

  bool _resubscribeScheduled = false;

  /// ⚠️ একাধিক stream একসাথে ভেঙে গেলে (একই root cause-এ, যেমন session
  /// পুরো invalid হয়ে গেলে) — বারবার resubscribe না করে debounce করা,
  /// একটাই resubscribe cycle-এ সব stream আবার সেট হয়ে যাবে যেহেতু
  /// `_subscribeAll()` তিনটাই একসাথে re-listen করে।
  void _scheduleResubscribe({required String reason}) {
    if (_disposed || _resubscribeScheduled) return;
    _resubscribeScheduled = true;

    Future.delayed(const Duration(milliseconds: 500), () {
      _resubscribeScheduled = false;
      if (_disposed) return;

      _resubscribeCount++;
      _lastResubscribeAt = DateTime.now();
      AppLogger.playback(
        '[AudioSessionManager] resubscribing (reason=$reason, '
        'count=$_resubscribeCount)',
      );
      _subscribeAll();
    });
  }

  /// ⚠️ Periodic health-check — শুধু onDone/onError-এর উপর নির্ভর করা
  /// যথেষ্ট না, কারণ platform channel stream silently "dead" হয়ে যেতে
  /// পারে (আর কোনো event delivered হয় না) onDone/onError কোনোটাই fire
  /// না করে। এই timer কোনো "sanity event" পাঠায় না (audio_session-এ
  /// সেরকম synthetic-event API নেই), বরং শুধু metrics log করে যাতে
  /// bug আবার হলে log থেকে ধরা যায় ঠিক কখন event আসা বন্ধ হয়েছিল।
  /// প্রকৃত recovery এখনো onDone/onError guard দিয়েই হয় — এই timer
  /// diagnostic, active-recovery না (audio_session platform limitation:
  /// stream "is it still alive" সরাসরি জিজ্ঞেস করার কোনো API নেই)।
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      if (_disposed) return;
      AppLogger.playback(
        '[AudioSessionManager] health-check: alive=$isSubscriptionAlive, '
        'lastInterruption=$_lastInterruptionEventAt, '
        'lastNoisy=$_lastNoisyEventAt, '
        'lastDeviceChange=$_lastDeviceChangeEventAt, '
        'resubscribeCount=$_resubscribeCount, '
        'lastResubscribe=$_lastResubscribeAt',
      );

      // ⚠️ Defensive — subscription object paused অবস্থায় আটকে থাকলে
      // (খুবই বিরল, কিন্তু isPaused true মানে event আসলেও deliver
      // হবে না) জোর করে resubscribe।
      if (!isSubscriptionAlive) {
        AppLogger.playback(
          '[AudioSessionManager] health-check detected dead subscription '
          '— forcing resubscribe',
        );
        _scheduleResubscribe(reason: 'health-check dead subscription');
      }
    });
  }

  void _onInterruptionEvent(AudioInterruptionEvent event) {
    _lastInterruptionEventAt = DateTime.now();
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          AppLogger.playback('[AudioSessionManager] duck begin');
          _audioFocusController.add(AudioFocusSignal.duck);
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          AppLogger.playback(
            '[AudioSessionManager] call/interruption begin (pause)',
          );
          _audioFocusController.add(AudioFocusSignal.callInterruption);
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          AppLogger.playback('[AudioSessionManager] duck end');
          _audioFocusController.add(AudioFocusSignal.gained);
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          AppLogger.playback('[AudioSessionManager] call/interruption end');
          _audioFocusController.add(AudioFocusSignal.callEnded);
          break;
      }
    }
  }

  void _onBecomingNoisy() {
    _lastNoisyEventAt = DateTime.now();
    AppLogger.playback(
      '[AudioSessionManager] becoming noisy (headphone/Bluetooth '
      'disconnected) — pause',
    );
    _audioFocusController.add(AudioFocusSignal.deviceDisconnected);
  }

  void _onDevicesChanged(AudioDevicesChangedEvent event) {
    _lastDeviceChangeEventAt = DateTime.now();
    if (event.devicesAdded.isEmpty) return;
    AppLogger.playback(
      '[AudioSessionManager] device added (${event.devicesAdded.length}) '
      '— possible reconnect',
    );
    _audioFocusController.add(AudioFocusSignal.deviceReconnected);
  }

  Future<void> dispose() async {
    _disposed = true;
    _healthCheckTimer?.cancel();
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    await _devicesChangedSub?.cancel();
    await _audioFocusController.close();
    // ⚠️ setActive(false) ইচ্ছাকৃতভাবে এখানেও কল করা হচ্ছে না যদি
    // audio_service এখনো চলমান থাকে — dispose() শুধু app সম্পূর্ণ বন্ধ
    // হওয়ার সময় কল হওয়া উচিত (TeloPlayAudioHandler.disposeHandler()
    // থেকে), যেটা এমনিতেই পুরো process kill-এর কাছাকাছি সময়।
  }
}