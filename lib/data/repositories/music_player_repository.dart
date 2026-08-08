import 'dart:async' show StreamSubscription, StreamController, Timer, unawaited;
import 'dart:math' show Random;

import 'package:media_kit/media_kit.dart';

import '../../core/logging/app_logger.dart';
import '../../core/playback/playback_engine.dart';
import '../../core/playback/buffer_health_monitor.dart';
import '../../core/playback/preload_manager.dart';
import '../../models/now_playing_model.dart';
import '../../models/buffer_state_model.dart';
import '../../services/behaviour_tracking_service.dart';
import '../../services/performance_service.dart';
import '../../services/cache_service.dart';
import 'queue_repository.dart';
import 'settings_repository.dart';

class MusicPlayerRepository {
  final PlaybackEngine _engine;
  final Player _player;

  final QueueRepository? _queueRepository;

  final BehaviourTrackingService? _behaviourTracking;

  final SettingsRepository? _settingsRepository;

  final CacheService? _cacheService;

  bool _initialized = false;

  bool _disposed = false;

  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _positionSub;

  int _playRequestToken = 0;

  NowPlaying _nowPlaying = NowPlaying.idle;
  NowPlaying get nowPlaying => _nowPlaying;

  PlaybackSource _currentPlaybackSource = PlaybackSource.online;

  final _nowPlayingController = StreamController<NowPlaying>.broadcast();
  Stream<NowPlaying> get nowPlayingStream => _nowPlayingController.stream;

  final _playbackErrorController = StreamController<PlaybackError>.broadcast();
  Stream<PlaybackError> get playbackErrorStream => _playbackErrorController.stream;

  void _setNowPlaying(NowPlaying value) {
    _nowPlaying = value;
    _nowPlayingController.add(value);
  }

  bool _isResolvingTrack = false;

  final _isResolvingController = StreamController<bool>.broadcast();
  Stream<bool> get isResolvingStream => _isResolvingController.stream;

  void _setResolving(bool value) {
    if (_isResolvingTrack == value) return;
    _isResolvingTrack = value;
    _isResolvingController.add(value);
  }

  void _finishResolvingIfCurrent(int myToken) {
    if (myToken == _playRequestToken) {
      _setResolving(false);
    }
  }

  SearchResult? get currentTrack => _nowPlaying.track;

  Stream<SearchResult?> get currentTrackStream =>
      nowPlayingStream.map((np) => np.track);

  final List<SearchResult> _queue = [];
  List<SearchResult> get queue => List.unmodifiable(_queue);
  int _queueIndex = -1;
  int get queueIndex => _queueIndex;

  // ⚠️ Context-based Queue (Phase 1 fix) — কোন context থেকে বর্তমান
  // queue populate হয়েছে (search/favorites/playlist ইত্যাদি)। এটা
  // in-memory-only — persist/sync করা হয় না (দেখো QueueSource enum-এর
  // নোট, playback_engine.dart)। restoreQueue() app restart-এ এটা
  // জানতে পারে না বলে unknown-এই থাকবে, যেটা ঠিক আছে কারণ এটা শুধু
  // UI hint, playback correctness এর উপর নির্ভর করে না।
  QueueSource _queueSource = QueueSource.unknown;
  QueueSource get queueSource => _queueSource;

  final _queueController = StreamController<List<SearchResult>>.broadcast();
  Stream<List<SearchResult>> get queueStream => _queueController.stream;

  void _notifyQueueChanged() {
    _queueController.add(List.unmodifiable(_queue));
  }

  static const _positionSaveInterval = Duration(seconds: 5);
  DateTime? _lastPositionSaveAt;

  static const _resumeMinPosition = Duration(seconds: 15);
  static const _resumeMaxFraction = 0.95;

  final _resumePromptController =
      StreamController<ResumePrompt?>.broadcast();
  Stream<ResumePrompt?> get resumePromptStream =>
      _resumePromptController.stream;
  ResumePrompt? _pendingResumePrompt;
  ResumePrompt? get pendingResumePrompt => _pendingResumePrompt;

  String? _promptShownForTrackId;

  void _setResumePrompt(ResumePrompt? prompt) {
    _pendingResumePrompt = prompt;
    _resumePromptController.add(prompt);
  }

  static const _kSettingShuffleEnabled = 'shuffle_enabled';
  static const _kSettingRepeatMode = 'repeat_mode';
  static const _kSettingPlaybackSpeed = 'playback_speed';

  bool _shuffleEnabled = false;
  bool get shuffleEnabled => _shuffleEnabled;

  final _shuffleEnabledController = StreamController<bool>.broadcast();
  Stream<bool> get shuffleEnabledStream => _shuffleEnabledController.stream;

  List<int>? _shuffleOrder;
  int _shufflePosition = -1;

  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  PlaybackRepeatMode get repeatMode => _repeatMode;

  final _repeatModeController = StreamController<PlaybackRepeatMode>.broadcast();
  Stream<PlaybackRepeatMode> get repeatModeStream => _repeatModeController.stream;

  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  final _playbackSpeedController = StreamController<double>.broadcast();
  Stream<double> get playbackSpeedStream => _playbackSpeedController.stream;

  // ⚠️ Phase 6 (Batch 4) — Volume foundation। _player.setVolume() লেখা
  // যায় কিন্তু media_kit থেকে current volume পড়ার কোনো stream নেই,
  // তাই নিজেদের local source-of-truth রাখা হচ্ছে (write-through:
  // setVolume() কল হলেই এখানে + player দুটোতেই আপডেট হয়)। Mute
  // toggle করার আগের volume মনে রাখতে _volumeBeforeMute ব্যবহার হয়
  // (audio-focus ducking-এর _volumeBeforeDuck-এর মতোই প্যাটার্ন,
  // ইচ্ছাকৃতভাবে আলাদা — duck আর mute দুটো independent concept,
  // একটা conflict করলে অন্যটার state overwrite করা উচিত না)।
  double _currentVolume = 100.0;
  bool _isMuted = false;
  double _volumeBeforeMute = 100.0;

  final _volumeController = StreamController<double>.broadcast();
  Stream<double> get volumeStream => _volumeController.stream;

  double get currentVolume => _currentVolume;
  bool get isMuted => _isMuted;

  Timer? _sleepTimer;
  Timer? _sleepTimerCountdownTicker;
  Timer? _sleepTimerFadeTicker;
  static const _sleepTimerFadeDuration = Duration(seconds: 5);
  static const _sleepTimerFadeStep = Duration(milliseconds: 250);
  double _volumeBeforeFade = 100.0;

  SleepTimerState _sleepTimerState = SleepTimerState.inactive;
  SleepTimerState get sleepTimerState => _sleepTimerState;

  final _sleepTimerController =
      StreamController<SleepTimerState>.broadcast();
  Stream<SleepTimerState> get sleepTimerStream => _sleepTimerController.stream;

  void _setSleepTimerState(SleepTimerState state) {
    _sleepTimerState = state;
    _sleepTimerController.add(state);
  }

  late final BufferHealthMonitor _bufferHealthMonitor;

  late final PreloadManager<ResolvedStream> _preloadManager;

  Stream<BufferState> get bufferStateStream => _bufferHealthMonitor.stateStream;
  BufferState get bufferState => _bufferHealthMonitor.state;

  StreamSubscription<AudioFocusSignal>? _audioFocusSub;
  bool _isDucking = false;
  double _volumeBeforeDuck = 100.0;
  static const _duckVolume = 35.0;

  bool _wasPlayingBeforeSystemInterruption = false;
  bool _systemInterruptionActive = false;
  int _deviceEventToken = 0;

  void _markUserInitiatedPause() {
    _systemInterruptionActive = false;
  }

  void _handleSystemInterruptionBegin() {
    if (_disposed) return;
    _deviceEventToken++;
    _wasPlayingBeforeSystemInterruption =
        _nowPlaying.status == NowPlayingStatus.playing;
    _systemInterruptionActive = true;

    if (_nowPlaying.track != null) {
      _setNowPlaying(
        NowPlaying(
          track: _nowPlaying.track,
          resolvedStream: _nowPlaying.resolvedStream,
          status: NowPlayingStatus.paused,
          playbackSource: _currentPlaybackSource,
        ),
      );
    }
    unawaited(_player.pause());
  }

  void _handleSystemInterruptionEnd() {
    if (_disposed) return;

    final shouldResume =
        _systemInterruptionActive && _wasPlayingBeforeSystemInterruption;

    _systemInterruptionActive = false;
    _wasPlayingBeforeSystemInterruption = false;

    if (!shouldResume) {
      AppLogger.playback(
        '[Bluetooth] interruption end — resume skipped '
        '(user had paused, or wasn\'t playing before interruption)',
      );
      return;
    }

    final myToken = _deviceEventToken;
    AppLogger.playback('[Bluetooth] interruption end — resuming playback');
    unawaited(Future(() async {
      if (_disposed || myToken != _deviceEventToken) return;
      if (_nowPlaying.track != null) {
        _setNowPlaying(
          NowPlaying(
            track: _nowPlaying.track,
            resolvedStream: _nowPlaying.resolvedStream,
            status: NowPlayingStatus.playing,
            playbackSource: _currentPlaybackSource,
          ),
        );
      }
      await _player.play();
    }));
  }

  static const _recentlyPlayedThreshold = Duration(seconds: 4);
  static const _completionThresholdFraction = 0.95;

  Timer? _recentlyPlayedThresholdTimer;
  String? _currentHistoryEntryId;
  DateTime? _currentSessionStartedAt;
  Duration _currentSessionLastKnownPosition = Duration.zero;

  int _sessionToken = 0;

  void _cancelRecentlyPlayedThresholdTimer() {
    _recentlyPlayedThresholdTimer?.cancel();
    _recentlyPlayedThresholdTimer = null;
  }

  void _scheduleRecentlyPlayedThreshold({
    required String videoId,
    required int myToken,
  }) {
    _cancelRecentlyPlayedThresholdTimer();
    _currentSessionStartedAt = DateTime.now();
    _currentSessionLastKnownPosition = Duration.zero;

    final mySessionToken = ++_sessionToken;

    _recentlyPlayedThresholdTimer = Timer(_recentlyPlayedThreshold, () async {
      if (_disposed ||
          myToken != _playRequestToken ||
          mySessionToken != _sessionToken) {
        return;
      }

      final id = await _behaviourTracking?.startPlaybackSession(
        songId: videoId,
      );

      if (_disposed ||
          myToken != _playRequestToken ||
          mySessionToken != _sessionToken) {
        return;
      }

      _currentHistoryEntryId = id;
    });
  }

  void _endCurrentPlaybackSession({
    required Duration? finalPosition,
    required Duration? trackDuration,
    required PlaybackOutcome fallbackOutcome,
  }) {
    _cancelRecentlyPlayedThresholdTimer();
    _sessionToken++;

    final historyEntryId = _currentHistoryEntryId;
    _currentHistoryEntryId = null;

    if (historyEntryId == null) {
      _currentSessionStartedAt = null;
      return;
    }

    final startedAt = _currentSessionStartedAt;
    _currentSessionStartedAt = null;

    final playedDuration = finalPosition ??
        (startedAt != null
            ? DateTime.now().difference(startedAt)
            : _currentSessionLastKnownPosition);

    PlaybackOutcome outcome = fallbackOutcome;
    if (fallbackOutcome != PlaybackOutcome.interrupted &&
        trackDuration != null &&
        trackDuration.inMilliseconds > 0 &&
        finalPosition != null) {
      final fraction = finalPosition.inMilliseconds / trackDuration.inMilliseconds;
      outcome = fraction >= _completionThresholdFraction
          ? PlaybackOutcome.completed
          : PlaybackOutcome.skipped;
    }

    unawaited(_behaviourTracking?.endPlaybackSession(
      historyEntryId: historyEntryId,
      outcome: outcome,
      playedDuration: playedDuration,
    ));
  }

  void _subscribeAudioFocus() {
    final stream = _engine.audioFocusStream;
    if (stream == null) {
      return;
    }

    _audioFocusSub = stream.listen((signal) {
      switch (signal) {
        case AudioFocusSignal.duck:
          _handleDuck();
          break;
        case AudioFocusSignal.transientLoss:
          AppLogger.playback(
            '[audio-focus] deprecated transientLoss signal received — '
            'routing through conditional-resume flow',
          );
          _handleSystemInterruptionBegin();
          break;
        case AudioFocusSignal.gained:
          _handleFocusGained();
          break;
        case AudioFocusSignal.callInterruption:
          _handleSystemInterruptionBegin();
          break;
        case AudioFocusSignal.callEnded:
          _handleSystemInterruptionEnd();
          break;
        case AudioFocusSignal.deviceDisconnected:
          _handleSystemInterruptionBegin();
          break;
        case AudioFocusSignal.deviceReconnected:
          _handleSystemInterruptionEnd();
          break;
      }
    });
  }

  void _handleDuck() {
    if (_disposed) return;
    if (!_isDucking) {
      _volumeBeforeDuck = 100.0;
      _isDucking = true;
    }
    AppLogger.playback('[audio-focus] ducking volume to $_duckVolume');
    unawaited(_player.setVolume(_duckVolume));
  }

  void _handleFocusGained() {
    if (_disposed) return;
    if (_isDucking) {
      AppLogger.playback('[audio-focus] focus gained — restoring volume');
      _isDucking = false;
      unawaited(_player.setVolume(_volumeBeforeDuck));
    }
  }

  MusicPlayerRepository(
    this._engine, [
    this._queueRepository,
    this._behaviourTracking,
    this._settingsRepository,
    this._cacheService,
  ]) : _player = Player() {
    _bufferHealthMonitor = BufferHealthMonitor(_player)
      ..onBufferStarvation = _handleBufferStarvation
      ..start();
    _preloadManager = PreloadManager<ResolvedStream>(_engine.resolveStream);

    _completedSub = _player.stream.completed.listen((completed) async {
      if (!completed) return;

      // ⚠️ Bug fix — end-of-stream false-completion race। media_kit
      // track শেষ হওয়ার প্রায় একই মুহূর্তে সংক্ষিপ্ত সময়ের জন্য
      // buffering:true fire করতে পারে (end-of-stream-কে rebuffering
      // ভেবে ভুল করে), যেটা completed:true event-এর সাথে race করে।
      // Log-এ দেখা গেছে এই blip মাত্র ~20-30ms-এই নিজে থেকে সেটেল হয়ে
      // যায় (buffering ফিরে false হয়ে যায়) — কিন্তু আগে এখানে সাথে
      // সাথে `isCurrentlyBuffering` চেক করা হতো, যেটা সেই blip-এর
      // মাঝখানে পড়ে গিয়ে genuine completion-কেও false-positive stall
      // হিসেবে ধরে ফেলত, ফলে auto-next/repeat কখনোই ট্রিগার হতো না।
      //
      // Fix: সাথে সাথে সিদ্ধান্ত না নিয়ে ছোট grace delay (৮০ms, log-এ
      // দেখা blip duration-এর চেয়ে বেশ কয়েকগুণ বেশি) দিয়ে buffering
      // flag আবার চেক করা হচ্ছে। genuine stall হলে এই delay-এর পরেও
      // buffering true-ই থাকবে (stall সাধারণত সেকেন্ডের অর্ডারে হয়,
      // ৮০ms-এ সেটেল হয় না), তাই real stall এখনও সঠিকভাবে ধরা পড়বে।
      await Future.delayed(const Duration(milliseconds: 80));

      if (_disposed) return;

      if (_bufferHealthMonitor.isCurrentlyBuffering ||
          !_bufferHealthMonitor.hasPlaybackPositionAdvanced) {
        AppLogger.playback(
          '[buffer-health] completed=true ignored — buffering active or '
          'playback never advanced (likely stall, not genuine completion)',
        );
        return;
      }

      final finishedTrack = _nowPlaying.track;
    

      if (finishedTrack != null) {
        _endCurrentPlaybackSession(
          finalPosition: finishedTrack.duration,
          trackDuration: finishedTrack.duration,
          fallbackOutcome: PlaybackOutcome.completed,
        );
      }

      if (_repeatMode == PlaybackRepeatMode.one && finishedTrack != null) {
        unawaited(
          playVideoId(finishedTrack.videoId, trackInfo: finishedTrack),
        );
        return;
      }

      final hasNext = _hasNextTrack();

      if (hasNext) {
        next();
        return;
      }

      if (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty) {
        if (_shuffleOrder != null) {
          _shufflePosition = 0;
          _queueIndex = _shuffleOrder![_shufflePosition];
        } else {
          _queueIndex = 0;
        }
        unawaited(playFromQueue(_queueIndex));
        return;
      }

      _setNowPlaying(
        NowPlaying(
          track: _nowPlaying.track,
          resolvedStream: _nowPlaying.resolvedStream,
          status: NowPlayingStatus.paused,
          playbackSource: _currentPlaybackSource,
        ),
      );
    });

    _positionSub = _player.stream.position.listen((pos) {
      _currentSessionLastKnownPosition = pos;
      _maybePersistPosition(pos);
    });

    unawaited(_loadPersistedPreferences());
  }

  Future<void> _loadPersistedPreferences() async {
    if (_settingsRepository == null) return;
    try {
      final values = await _settingsRepository.getValues([
        _kSettingShuffleEnabled,
        _kSettingRepeatMode,
        _kSettingPlaybackSpeed,
      ]);

      if (_disposed) return;

      final shuffleStr = values[_kSettingShuffleEnabled];
      if (shuffleStr == 'true') {
        _shuffleEnabled = true;
        _shuffleEnabledController.add(true);
        _regenerateShuffleOrder();
      }

      final repeatStr = values[_kSettingRepeatMode];
      if (repeatStr != null) {
        _repeatMode = PlaybackRepeatMode.values.firstWhere(
          (m) => m.name == repeatStr,
          orElse: () => PlaybackRepeatMode.off,
        );
        _repeatModeController.add(_repeatMode);
      }

      final speedStr = values[_kSettingPlaybackSpeed];
      if (speedStr != null) {
        final parsed = double.tryParse(speedStr);
        if (parsed != null && parsed > 0) {
          _playbackSpeed = parsed;
          _playbackSpeedController.add(_playbackSpeed);
          unawaited(_player.setRate(_playbackSpeed));
        }
      }
    } catch (e) {
      AppLogger.error('Preference restore failed', e);
    }
  }

  void _regenerateShuffleOrder() {
    if (_queue.isEmpty) {
      _shuffleOrder = null;
      _shufflePosition = -1;
      return;
    }

    final indices = List<int>.generate(_queue.length, (i) => i);
    final random = Random();
    for (var i = indices.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tmp = indices[i];
      indices[i] = indices[j];
      indices[j] = tmp;
    }

    if (_queueIndex >= 0 && _queueIndex < _queue.length) {
      indices.remove(_queueIndex);
      indices.insert(0, _queueIndex);
      _shufflePosition = 0;
    } else {
      _shufflePosition = -1;
    }

    _shuffleOrder = indices;
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    _shuffleEnabledController.add(enabled);

    if (enabled) {
      _regenerateShuffleOrder();
    } else {
      _shuffleOrder = null;
      _shufflePosition = -1;
    }

    unawaited(_settingsRepository?.setValue(
      _kSettingShuffleEnabled,
      enabled.toString(),
    ));
  }

  bool _hasNextTrack() {
    if (_shuffleOrder != null) {
      return _shufflePosition + 1 < _shuffleOrder!.length;
    }
    return _queueIndex + 1 < _queue.length;
  }

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _repeatMode = mode;
    _repeatModeController.add(mode);
    unawaited(_settingsRepository?.setValue(_kSettingRepeatMode, mode.name));
  }

  Future<void> cycleRepeatMode() async {
    final next = switch (_repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    await setRepeatMode(next);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (speed <= 0) return;
    _playbackSpeed = speed;
    _playbackSpeedController.add(speed);
    if (!_disposed) {
      await _player.setRate(speed);
    }
    unawaited(_settingsRepository?.setValue(
      _kSettingPlaybackSpeed,
      speed.toString(),
    ));
  }

  void startSleepTimer(Duration duration) {
    _cancelSleepTimerInternal(resetState: false);

    final fadeStartDelay = duration > _sleepTimerFadeDuration
        ? duration - _sleepTimerFadeDuration
        : Duration.zero;

    _setSleepTimerState(SleepTimerState(remaining: duration));

    _sleepTimer = Timer(fadeStartDelay, () {
      _beginSleepTimerFade();
    });

    var remaining = duration;
    _sleepTimerCountdownTicker =
        Timer.periodic(const Duration(seconds: 1), (ticker) {
      if (_disposed || _sleepTimer == null) {
        ticker.cancel();
        return;
      }
      remaining -= const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        ticker.cancel();
        return;
      }
      _setSleepTimerState(SleepTimerState(
        remaining: remaining,
        isFading: remaining <= _sleepTimerFadeDuration,
      ));
    });
  }

  void _beginSleepTimerFade() {
    if (_disposed) return;
    _volumeBeforeFade = 100.0;
    _setSleepTimerState(SleepTimerState(
      remaining: _sleepTimerFadeDuration,
      isFading: true,
    ));

    final totalSteps = _sleepTimerFadeDuration.inMilliseconds /
        _sleepTimerFadeStep.inMilliseconds;
    var stepsElapsed = 0;

    _sleepTimerFadeTicker =
        Timer.periodic(_sleepTimerFadeStep, (ticker) async {
      if (_disposed) {
        ticker.cancel();
        return;
      }
      stepsElapsed++;
      final fraction = 1 - (stepsElapsed / totalSteps);
      final newVolume = (_volumeBeforeFade * fraction).clamp(0.0, 100.0);
      await _player.setVolume(newVolume);

      if (stepsElapsed >= totalSteps) {
        ticker.cancel();
        await _player.pause();
        await _player.setVolume(_volumeBeforeFade);
        _setSleepTimerState(SleepTimerState.inactive);
        _sleepTimer = null;
        _sleepTimerCountdownTicker?.cancel();
        _sleepTimerCountdownTicker = null;
        _sleepTimerFadeTicker = null;
      }
    });
  }

  void _cancelSleepTimerInternal({required bool resetState}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerCountdownTicker?.cancel();
    _sleepTimerCountdownTicker = null;
    _sleepTimerFadeTicker?.cancel();
    _sleepTimerFadeTicker = null;
    if (resetState) {
      _setSleepTimerState(SleepTimerState.inactive);
    }
  }

  void cancelSleepTimer() {
    final wasFading = _sleepTimerState.isFading;
    _cancelSleepTimerInternal(resetState: true);
    if (wasFading && !_disposed) {
      unawaited(_player.setVolume(_volumeBeforeFade));
    }
  }

  void _maybePersistPosition(Duration position) {
    if (_queueRepository == null) return;
    final track = _nowPlaying.track;
    if (track == null || _nowPlaying.status != NowPlayingStatus.playing) {
      return;
    }

    final now = DateTime.now();
    if (_lastPositionSaveAt != null &&
        now.difference(_lastPositionSaveAt!) < _positionSaveInterval) {
      return;
    }
    _lastPositionSaveAt = now;

    unawaited(_queueRepository
        .updatePlaybackPosition(
          songId: track.videoId,
          positionMs: position.inMilliseconds,
        )
        .catchError((e) {
      AppLogger.error('Position persist failed', e);
    }));
  }

  Future<void> restoreQueue() async {
    if (_queueRepository == null) return;
    try {
      final restored = await _queueRepository.loadQueue();
      if (restored.queue.isEmpty) return;

      _queue
        ..clear()
        ..addAll(restored.queue);
      _queueIndex = restored.currentIndex;
      _notifyQueueChanged();

      if (_shuffleEnabled) {
        _regenerateShuffleOrder();
      }

      AppLogger.playback(
        'Queue restored into repository: ${_queue.length} tracks, '
        'index=$_queueIndex',
      );
    } catch (e) {
      AppLogger.error('Queue restore failed', e);
    }
  }

  Future<void> _persistQueue() async {
    if (_queueRepository == null) return;
    try {
      await _queueRepository.saveQueue(_queue, _queueIndex);
    } catch (e) {
      AppLogger.error('Queue persist failed', e);
    }
  }

  Stream<Duration> get positionStream => _player.stream.position;
  Stream<Duration?> get durationStream => _player.stream.duration;
  Stream<bool> get playingStream => _player.stream.playing;
  Stream<bool> get bufferingStream => _player.stream.buffering;
  Stream<String> get errorStream => _player.stream.error;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _engine.initialize();
    _initialized = true;
    _subscribeAudioFocus();
  }

  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    await _ensureInitialized();
    final results = await _engine.search(query, limit: limit);

    unawaited(_behaviourTracking?.recordSearch(
      query: query,
      resultCount: results.length,
    ));

    return results;
  }

  Future<List<String>> searchSuggestions(String query) {
    return _engine.searchSuggestions(query);
  }

  static const _maxRetries = 2;
  static const _retryDelays = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
  ];

  Future<ResolvedStream> _resolveWithRetry(String videoId) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await _engine.resolveStream(videoId);
      } catch (e) {
        lastError = e;
        final isLastAttempt = attempt == _maxRetries;
        AppLogger.playback(
          '[${_engine.engineLabel}] resolve attempt ${attempt + 1}/'
          '${_maxRetries + 1} failed for videoId=$videoId'
          '${isLastAttempt ? ' (giving up)' : ', retrying...'}',
        );
        if (isLastAttempt) break;
        await Future.delayed(_retryDelays[attempt]);
      }
    }
    if (lastError is PlaybackEngineException) throw lastError;
    throw PlaybackEngineException(
      'Stream resolve ব্যর্থ ($_maxRetries retry-এর পরেও)',
      cause: lastError,
    );
  }

  bool _starvationRecoveryActive = false;

  static const _starvationRetryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
    Duration(seconds: 30),
  ];

  void _handleBufferStarvation(Duration lastKnownPosition) {
    if (_disposed) return;
    final track = _nowPlaying.track;
    if (track == null || _nowPlaying.status != NowPlayingStatus.playing) {
      return;
    }

    AppLogger.playback(
      '[buffer-recovery] starvation detected for ${track.videoId}, '
      'attempting stream re-resolve (resume position=$lastKnownPosition)',
    );

    _starvationRecoveryActive = true;

    final myToken = _playRequestToken;
    unawaited(_attemptStarvationRecovery(
      videoId: track.videoId,
      resumePosition: lastKnownPosition,
      myToken: myToken,
      retryAttempt: 0,
    ));
  }

  Future<void> _attemptStarvationRecovery({
    required String videoId,
    required Duration resumePosition,
    required int myToken,
    required int retryAttempt,
  }) async {
    if (_disposed || myToken != _playRequestToken) {
      AppLogger.playback('[buffer-recovery] stale, discarding');
      return;
    }

    try {
      ResolvedStream resolved;
      var recoverySource = PlaybackSource.online;

      final cachedPath = await _cacheService?.checkCachedFile(videoId);
      if (cachedPath != null) {
        AppLogger.playback(
          '[buffer-recovery] cache-fallback — network resolve skipped, '
          'playing from local file: $videoId',
        );
        resolved = ResolvedStream(
          streamUrl: cachedPath,
          sourceLabel: 'local-cache',
        );
        recoverySource = PlaybackSource.cacheFallback;
      } else {
        resolved = await _resolveWithRetry(videoId);
      }

      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback('[buffer-recovery] stale, discarding');
        return;
      }
      await _player.stop();
      await _player.open(Media(resolved.streamUrl), play: false);

      try {
        await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        AppLogger.playback(
          '[buffer-recovery] duration-ready wait timed out, '
          'proceeding without confirmed seek target',
        );
      }

      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback('[buffer-recovery] stale post-load, discarding');
        return;
      }

      await _player.seek(resumePosition);
      await _player.play();

      _currentPlaybackSource = recoverySource;

      if (_nowPlaying.track != null) {
        _setNowPlaying(
          NowPlaying(
            track: _nowPlaying.track,
            resolvedStream: resolved,
            status: NowPlayingStatus.playing,
            playbackSource: recoverySource,
          ),
        );
      }

      AppLogger.playback(
        '[buffer-recovery] recovered: $videoId '
        '(source=$recoverySource, seeked to $resumePosition, '
        'attempt=${retryAttempt + 1})',
      );
      _starvationRecoveryActive = false;
    } catch (e) {
      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback('[buffer-recovery] stale on failure, discarding');
        return;
      }

      if (_nowPlaying.track != null) {
        _setNowPlaying(
          NowPlaying(
            track: _nowPlaying.track,
            resolvedStream: _nowPlaying.resolvedStream,
            status: NowPlayingStatus.paused,
            playbackSource: _currentPlaybackSource,
          ),
        );
      }

      final delayIndex = retryAttempt.clamp(
        0,
        _starvationRetryDelays.length - 1,
      );
      final delay = _starvationRetryDelays[delayIndex];

      AppLogger.playback(
        '[buffer-recovery] attempt ${retryAttempt + 1} failed '
        '(${e.runtimeType}), retrying in ${delay.inSeconds}s '
        '(waiting for network to return)',
      );

      await Future.delayed(delay);

      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback(
          '[buffer-recovery] stale after retry delay, discarding',
        );
        return;
      }

      unawaited(_attemptStarvationRecovery(
        videoId: videoId,
        resumePosition: resumePosition,
        myToken: myToken,
        retryAttempt: retryAttempt + 1,
      ));
    }
  }

  Future<void> _evaluateResumeState({
    required String videoId,
    Duration? trackDuration,
  }) async {
    _setResumePrompt(null);

    if (_promptShownForTrackId != null &&
        _promptShownForTrackId != videoId) {
      _promptShownForTrackId = null;
    }

    if (_queueRepository == null) return;

    if (_promptShownForTrackId == videoId) return;

    try {
      final saved = await _queueRepository.getCurrentPlaybackPosition();

      if (_disposed) return;

      if (saved == null || saved.songId != videoId) return;

      final positionMs = saved.positionMs;
      if (positionMs < _resumeMinPosition.inMilliseconds) {
        return;
      }

      if (trackDuration != null && trackDuration.inMilliseconds > 0) {
        final fraction = positionMs / trackDuration.inMilliseconds;
        if (fraction >= _resumeMaxFraction) {
          return;
        }
      }

      _promptShownForTrackId = videoId;

      _setResumePrompt(ResumePrompt(
        songId: videoId,
        position: Duration(milliseconds: positionMs),
        trackDuration: trackDuration,
      ));
    } catch (e) {
      AppLogger.error('Resume position check failed', e);
    }
  }

  Future<void> acceptResume() async {
    final prompt = _pendingResumePrompt;
    if (prompt == null) return;
    if (_nowPlaying.track?.videoId != prompt.songId) {
      _setResumePrompt(null);
      return;
    }
    _setResumePrompt(null);
    if (_disposed) return;
    await _player.seek(prompt.position);
  }

  void dismissResume() {
    _setResumePrompt(null);
  }

  void _triggerNextTrackPreload() {
    if (PerformanceService.instance.isLowRamMode) {
      AppLogger.playback(
        '[preload] skipped — low RAM mode active',
      );
      return;
    }

    String? nextVideoId;

    if (_shuffleOrder != null) {
      if (_shufflePosition + 1 < _shuffleOrder!.length) {
        final idx = _shuffleOrder![_shufflePosition + 1];
        if (idx >= 0 && idx < _queue.length) {
          nextVideoId = _queue[idx].videoId;
        }
      }
    } else if (_queueIndex + 1 < _queue.length) {
      nextVideoId = _queue[_queueIndex + 1].videoId;
    }

    if (nextVideoId != null) {
      _preloadManager.preload(nextVideoId);
    }

    unawaited(_cacheUpcomingTracks());
  }

  Future<void> _cacheUpcomingTracks() async {
    if (_cacheService == null) return;
    if (PerformanceService.instance.isLowRamMode) return;

    final upcoming = <SearchResult>[];

    if (_shuffleOrder != null) {
      for (var i = 1; i <= 3; i++) {
        final pos = _shufflePosition + i;
        if (pos >= _shuffleOrder!.length) break;
        final idx = _shuffleOrder![pos];
        if (idx >= 0 && idx < _queue.length) {
          upcoming.add(_queue[idx]);
        }
      }
    } else {
      for (var i = 1; i <= 3; i++) {
        final idx = _queueIndex + i;
        if (idx >= _queue.length) break;
        upcoming.add(_queue[idx]);
      }
    }

    if (upcoming.isEmpty) return;

    final tracksWithUrls = <({String videoId, String streamUrl})>[];

    for (final track in upcoming) {
      final alreadyCached =
          await _cacheService.checkCachedFile(track.videoId);
      if (alreadyCached != null) continue;

      try {
        final resolved = await _engine.resolveStream(track.videoId);
        tracksWithUrls.add((
          videoId: track.videoId,
          streamUrl: resolved.streamUrl,
        ));
      } catch (e) {
        AppLogger.playback(
          '[cache] preload-resolve failed for ${track.videoId}: $e',
        );
      }
    }

    if (tracksWithUrls.isNotEmpty) {
      await _cacheService.preloadUpcoming(tracksWithUrls);
    }
  }

  Future<void> playVideoId(String videoId, {SearchResult? trackInfo}) async {
    await _ensureInitialized();

    AppLogger.playback(
      '[${_engine.engineLabel}] playVideoId requested: $videoId',
    );

    final previousTrack = _nowPlaying.track;

    if (previousTrack != null &&
        previousTrack.videoId != videoId &&
        _nowPlaying.status == NowPlayingStatus.playing) {
      _endCurrentPlaybackSession(
        finalPosition: _currentSessionLastKnownPosition,
        trackDuration: previousTrack.duration,
        fallbackOutcome: PlaybackOutcome.skipped,
      );
    }

    _systemInterruptionActive = false;
    _wasPlayingBeforeSystemInterruption = false;
    _deviceEventToken++;
    _preloadManager.invalidate();

    final myToken = ++_playRequestToken;
    _starvationRecoveryActive = false;

    final provisionalTrack = trackInfo ??
        _nowPlaying.track ??
        SearchResult(
          videoId: videoId,
          title: videoId,
          author: 'Unknown',
          thumbnail: 'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
        );

    _currentPlaybackSource = PlaybackSource.online;

    // ⚠️ Bug fix — optimistic UI বাদ। আগে এখানে track: provisionalTrack
// (নতুন B) সেট হতো resolve শুরু হওয়ার আগেই — resolve সফল হলে (বেশিরভাগ
// সময়) কোনো সমস্যা ছিল না, কিন্তু resolve ব্যর্থ হলে (retry loop শেষ
// হতে ৪-৫ সেকেন্ড লাগে) UI ততক্ষণ ভুল করে B-এর thumbnail/title দেখাত,
// তারপর হঠাৎ A-তে revert করত — একটা দৃশ্যমান glitch।
//
// এখন: track আগের track-ই (previousTrack) রাখা হচ্ছে, শুধু status →
// resolving। UI-তে A-এর thumbnail/title অপরিবর্তিত থাকবে যতক্ষণ না
// resolve সত্যিই সফল হয় (নিচে, `_player.play()`-এর পরের
// `_setNowPlaying()`-এ প্রথমবার track: provisionalTrack সেট হয়)।
// resolve ব্যর্থ হলে previousTrack এমনিতেই আগে থেকে সেট আছে, তাই
// catch ব্লকের revert কল আর কোনো visible change ঘটায় না (no-op-এর
// মতো, harmless)।
_setNowPlaying(
  NowPlaying(
    track: previousTrack,
    status: NowPlayingStatus.resolving,
    resolvedStream: _nowPlaying.resolvedStream,
    errorMessage: null,
    playbackSource: _currentPlaybackSource,
  ),
);

    // ⚠️ Bug fix — Songs টেবিলে upsert এখানে, network resolve শুরুর আগে।
    // আগে playVideoId() কখনো Songs row নিশ্চিত করত না (শুধু addFavorite()/
    // saveQueue() করত, আর playVideoId() কোনোটার completion-এর জন্য অপেক্ষা
    // করত না) — ফলে cacheService.cacheTrack()→markCached() ও
    // BehaviourTrackingService-এর HistoryEntries insert দুটোই এমন একটা
    // videoId রেফার করত যার Songs টেবিলে কোনো matching row ছিল না।
    // markCached() silently no-op হতো (UPDATE...WHERE কোনো row না পেয়ে),
    // আর getRecentlyPlayed()/getHistory()-এর innerJoin(songs) সেই history
    // row বাদ দিয়ে দিত — দুটো bug-এরই একক root cause।
    // QueueRepository.upsertSong() reuse করা হচ্ছে (একই FK-satisfying
    // upsert, duplicate logic এড়াতে)। await করা হচ্ছে যাতে পরের সব ধাপ
    // (resolve, cache, history) নিশ্চিতভাবে এর পরে চলে — এটা সস্তা, local
    // Drift write, network call না, তাই playback-শুরুর latency-তে
    // উল্লেখযোগ্য প্রভাব ফেলবে না।
    if (_queueRepository != null) {
      try {
        await _queueRepository.upsertSong(provisionalTrack);
      } catch (e) {
        AppLogger.error('Songs upsert failed for videoId=$videoId', e);
        // non-fatal — playback চলতে থাকবে, শুধু cache/history bookkeeping
        // miss হতে পারে এই track-এর জন্য, ঠিক আগের (buggy) আচরণের মতোই।
      }
    }

    _setResolving(true);

    try {
      ResolvedStream resolved;
      final preloaded = _preloadManager.takeIfMatches(videoId);
      if (preloaded != null) {
        resolved = preloaded;
      } else {
        final cacheHit = await _cacheService?.checkCachedFile(videoId);
        if (cacheHit != null) {
          AppLogger.playback(
            '[cache] hit — playing from local file: $videoId',
          );
          resolved = ResolvedStream(
            streamUrl: cacheHit,
            sourceLabel: 'local-cache',
          );
        } else {
          resolved = await _resolveWithRetry(videoId);
        }
      }

      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback(
          '[${_engine.engineLabel}] stale/disposed playVideoId ignored (post-resolve): $videoId',
        );
        return;
      }

      await _player.stop();
      await _player.open(Media(resolved.streamUrl));

      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback(
          '[${_engine.engineLabel}] stale/disposed playVideoId ignored (post-open): $videoId',
        );
        return;
      }

      // ⚠️ Bug fix — Bluetooth playback start latency optimization।
      // আগে এখানে `setVolume(100.0)`, `setRate()`, এবং
      // `_evaluateResumeState()` (একটা Drift DB query!) — এই তিনটাই
      // `open()`-এর পরে কিন্তু `play()`-এর *আগে* awaited হতো। প্রতিটাই
      // media_kit-এর সাথে synchronous round-trip (platform channel/
      // native call), যেগুলো Bluetooth output-এ audio route negotiation
      // চলাকালীন playback-start command-কে পিছিয়ে দিত, ফলে প্রতিটা
      // track শুরুতে একটা ছোট (~০.৫-০.৮s) glitch/gap অনুভূত হতো —
      // Bluetooth device যখন নতুন stream শুরুর signal ঠিক সেই মুহূর্তে
      // পেত, তার ঠিক পরপরই আরও কয়েকটা native call আসায় re-sync ঘটত।
      //
      // Fix: `play()` কে যত দ্রুত সম্ভব `open()`-এর পরে কল করা হচ্ছে,
      // যাতে audio route/codec negotiation-এর সাথে playback-start
      // command-এর মধ্যে ন্যূনতম gap থাকে। Volume/rate reset এবং resume-
      // check এখন `play()`-এর *পরে* করা হচ্ছে — এগুলো non-critical,
      // playback ইতিমধ্যে audible হয়ে যাওয়ার পরেও করলে কোনো সমস্যা নেই
      // (volume 100→100 হলে কোনো audible glitch নেই, playbackSpeed
      // পরিবর্তন এবং resume-seek উভয়ই play()-এর পরে ঘটলে user খেয়ালই
      // করবে না, কারণ এগুলো milliseconds-এর মধ্যেই ঘটে)।
      await _player.play();

      _isDucking = false;
      unawaited(_player.setVolume(_currentVolume));

      if (_playbackSpeed != 1.0) {
        unawaited(_player.setRate(_playbackSpeed));
      }

      // Resume-check এখনো await করা হচ্ছে (পরের ধাপ — NowPlaying emit,
      // _scheduleRecentlyPlayedThreshold ইত্যাদির আগে) কিন্তু play()
      // এর *পরে*, তাই আর playback-start-কে block করছে না।
      unawaited(_evaluateResumeState(
        videoId: videoId,
        trackDuration: provisionalTrack.duration,
      ));

      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback(
          '[${_engine.engineLabel}] stale/disposed playVideoId ignored (post-play): $videoId',
        );
        return;
      }

      _setNowPlaying(
        NowPlaying(
          track: provisionalTrack,
          resolvedStream: resolved,
          status: NowPlayingStatus.playing,
          playbackSource: PlaybackSource.online,
        ),
      );

      _bufferHealthMonitor.resetForNewTrack();
      _triggerNextTrackPreload();

      if (resolved.sourceLabel != 'local-cache') {
        unawaited(_cacheService?.cacheTrack(
              videoId: videoId,
              streamUrl: resolved.streamUrl,
              priority: CachePriority.currentPlaying,
            ) ??
            Future.value());
      }

      _scheduleRecentlyPlayedThreshold(videoId: videoId, myToken: myToken);

      AppLogger.playback(
        '[${_engine.engineLabel}] playback started: $videoId '
        '(expiresIn=${resolved.expiresIn})',
      );
      _finishResolvingIfCurrent(myToken);
    } on PlaybackEngineException catch (e) {
      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback(
          '[${_engine.engineLabel}] stale/disposed playVideoId error ignored: $videoId',
        );
        return;
      }

      AppLogger.error('Playback failed for videoId=$videoId', e);

      // ⚠️ Bug fix — Fallback flow: online resolve ব্যর্থ হলে cache চেষ্টা
      // করা হচ্ছে (হয়তো videoId আগে কখনো cache হয়ে ছিল, network এখন নেই
      // কিন্তু ফাইল ডিস্কে আছে) — এতদিন এই path-এ কোনো cache-check ছিলই
      // না, resolve fail মানেই সরাসরি error state।
      final cachedPath = await _cacheService?.checkCachedFile(videoId);

      if (cachedPath != null && !_disposed && myToken == _playRequestToken) {
        AppLogger.playback(
          '[cache] fallback after resolve failure — playing from local file: $videoId',
        );
        try {
          await _player.stop();
          await _player.open(Media(cachedPath));
          await _player.play();

          _currentPlaybackSource = PlaybackSource.cacheFallback;
          final resolved = ResolvedStream(
            streamUrl: cachedPath,
            sourceLabel: 'local-cache',
          );

          _setNowPlaying(
            NowPlaying(
              track: provisionalTrack,
              resolvedStream: resolved,
              status: NowPlayingStatus.playing,
              playbackSource: PlaybackSource.cacheFallback,
            ),
          );

          _bufferHealthMonitor.resetForNewTrack();
          _scheduleRecentlyPlayedThreshold(videoId: videoId, myToken: myToken);

          AppLogger.playback(
            '[${_engine.engineLabel}] playback started via cache-fallback: $videoId',
          );
          _finishResolvingIfCurrent(myToken);
          return; // ✅ সফল — এখানেই থেমে যাওয়া, নিচের revert/error path না
        } catch (playError) {
          AppLogger.error(
            'Cache-fallback playback failed for videoId=$videoId',
            playError,
          );
          // cache file থাকা সত্ত্বেও play করা গেল না (corrupted file
          // ইত্যাদি) — নিচের revert/error path-এই পড়বে।
        }
      }

      if (_disposed || myToken != _playRequestToken) {
        AppLogger.playback(
          '[${_engine.engineLabel}] stale/disposed playVideoId error ignored (post-cache-attempt): $videoId',
        );
        return;
      }

      // ⚠️ Bug fix — online ও cache fallback দুটোই ব্যর্থ হলে আগের track-এ
      // revert করা হচ্ছে (silent — audio engine আসলে এখনও previousTrack-ই
      // বাজাচ্ছে, কারণ _player.stop()/open() এই catch-এর আগে কখনো কল হয়নি,
      // resolve সফল হলে তবেই হতো)। আগে এখানে NowPlaying.track =
      // provisionalTrack (নতুন, ব্যর্থ track) থেকে যেত, ফলে UI thumbnail/
      // title ভুল track দেখাত যখন audio previousTrack-ই চালিয়ে যাচ্ছিল।
      if (previousTrack != null) {
        _setNowPlaying(
          NowPlaying(
            track: previousTrack,
            resolvedStream: _nowPlaying.resolvedStream,
            status: NowPlayingStatus.playing,
            playbackSource: _currentPlaybackSource,
          ),
        );
      } else {
        _setNowPlaying(
          NowPlaying(
            track: null,
            status: NowPlayingStatus.idle,
          ),
        );
      }

      // ⚠️ Structured, user-friendly error event — UI নিজে ঠিক করবে কীভাবে
      // দেখাবে (Snackbar/Toast)। Technical exception message এখানে UI-কে
      // পাঠানো হচ্ছে না।
      _playbackErrorController.add(
        PlaybackError(
          'Unable to play this song',
          cause: e,
        ),
      );

      // rethrow করা হচ্ছে না ইচ্ছাকৃতভাবে — caller (_play() UI method)
      // আগে raw exception ধরে setState(_error) করত, এখন সেটা আর দরকার
      // নেই কারণ playbackErrorStream দিয়েই UI জানবে। rethrow রাখলে UI-এর
      // পুরনো _error box আর নতুন snackbar দুটোই একসাথে ফায়ার হয়ে যেত।
      _finishResolvingIfCurrent(myToken);
    }
  }

  Future<SearchResult> searchAndPlay(String query) async {
    final results = await search(query, limit: 1);
    if (results.isEmpty) {
      throw PlaybackEngineException('কোনো ফলাফল পাওয়া যায়নি query="$query"');
    }
    final result = results.first;
    await playVideoId(result.videoId, trackInfo: result);
    return result;
  }

  // ⚠️ Context-based Queue (Phase 1 fix) — Root cause: search/favorites/
  // downloads/playlist screen সরাসরি playVideoId() কল করত, _queue কখনো
  // populate না হয়েই — ফলে auto-next/repeat-all কাজ করত না (queue
  // হয় খালি, নয়তো পুরনো/ভুল track ধরে থাকত), repeat-one অংশ ঠিক ছিল
  // কারণ সেটা _queue-নির্ভর না (playVideoId নিজেই আবার resolve করে,
  // দেখো _completedSub-এর ভেতরের PlaybackRepeatMode.one শাখা)।
  //
  // এই একটা public method-ই এখন প্রতিটা screen থেকে ব্যবহার করা উচিত
  // যখনই কোনো list-এর ভেতর থেকে track tap হয় (Spotify/YouTube Music-এর
  // "play from this context" প্যাটার্ন) — পুরনো `playVideoId()` সরাসরি
  // কল করা উচিত না সেসব জায়গা থেকে আর। `playVideoId()` তবু বাইরে
  // exposed/backward-compatible থাকছে single-track/notification/
  // deep-link কেসের জন্য (দেখো ওর doc-comment)।
  //
  // Internal flow: existing playFromQueue()/_persistQueue()/shuffle-
  // regeneration reuse করা হচ্ছে — নতুন resolve/playback logic লাগেনি,
  // শুধু queue-population + entry-point টা centralize করা হলো।
  Future<void> playFromContext({
    required List<SearchResult> tracks,
    required int startIndex,
    QueueSource source = QueueSource.unknown,
  }) async {
    // 🔍 DEBUG — সাময়িক, bug ধরার জন্য। Fix হয়ে গেলে সরিয়ে ফেলবে।
    AppLogger.playback(
      '[DEBUG] playFromContext CALLED: source=$source, '
      'incoming tracks.length=${tracks.length}, startIndex=$startIndex, '
      'BEFORE _queue.length=${_queue.length}',
    );

    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) {
      AppLogger.playback(
        '[queue] playFromContext ignored — empty tracks or invalid '
        'startIndex=$startIndex (length=${tracks.length})',
      );
      return;
    }

    _queue
      ..clear()
      ..addAll(tracks);
    _queueSource = source;
    _notifyQueueChanged();
    unawaited(_persistQueue());

    if (_shuffleEnabled) {
      _regenerateShuffleOrder();
    }

    // 🔍 DEBUG — সাময়িক।
    AppLogger.playback(
      '[DEBUG] playFromContext AFTER assign: _queue.length=${_queue.length}, '
      '_queueIndex(before playFromQueue)=$_queueIndex',
    );

    AppLogger.playback(
      '[queue] playFromContext: source=$source, size=${tracks.length}, '
      'startIndex=$startIndex',
    );

    await playFromQueue(startIndex);

    // 🔍 DEBUG — সাময়িক, playFromQueue শেষে queue অবস্থা।
    AppLogger.playback(
      '[DEBUG] playFromContext AFTER playFromQueue: _queue.length=${_queue.length}, '
      '_queueIndex=$_queueIndex, hasNext=${_hasNextTrack()}',
    );
  }

  void addToQueue(SearchResult track) {
    _queue.add(track);
    if (_queue.length == 1) {
      _queueIndex = 0;
    }
    _notifyQueueChanged();
    unawaited(_persistQueue());

    if (_shuffleEnabled) {
      _regenerateShuffleOrder();
    }
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queueIndex = index;

    if (_shuffleOrder != null) {
      final pos = _shuffleOrder!.indexOf(index);
      _shufflePosition = pos >= 0 ? pos : 0;
    }

    await playVideoId(_queue[index].videoId, trackInfo: _queue[index]);
    if (_queueRepository != null) {
      unawaited(_queueRepository.updateCurrentIndex(index));
    }
  }

  Future<void> next() async {
    if (_shuffleOrder != null) {
      if (_shufflePosition + 1 >= _shuffleOrder!.length) {
        // ⚠️ Bug fix — repeat-all wrap-around এতদিন শুধু auto-completion
        // (_completedSub listener)-এ ছিল, manual next() button-এ ছিল
        // না। এখন shuffle-mode-এও queue শেষে repeat-all থাকলে প্রথম
        // shuffle position-এ (index 0, যেটা current track pin করা
        // থাকে _regenerateShuffleOrder()-এ) ফিরে যাবে।
        if (_repeatMode == PlaybackRepeatMode.all &&
            _shuffleOrder!.isNotEmpty) {
          _shufflePosition = 0;
          final targetIndex = _shuffleOrder![_shufflePosition];
          await playFromQueue(targetIndex);
        }
        return;
      }
      _shufflePosition++;
      final targetIndex = _shuffleOrder![_shufflePosition];
      await playFromQueue(targetIndex);
      return;
    }

    if (_queueIndex + 1 < _queue.length) {
      await playFromQueue(_queueIndex + 1);
      return;
    }

    // ⚠️ Bug fix — repeat-all wrap-around এতদিন শুধু auto-completion
    // (_completedSub listener)-এ ছিল, manual next() button চাপলে queue
    // শেষে থাকলে কিছুই হতো না, repeat-all mode-এ থাকা সত্ত্বেও। এখন
    // manual next এবং auto-next দুটোই একই wrap-around behavior পাবে।
    if (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty) {
      await playFromQueue(0);
    }
  }

  Future<void> previous() async {
    if (_shuffleOrder != null) {
      if (_shufflePosition - 1 < 0) return;
      _shufflePosition--;
      final targetIndex = _shuffleOrder![_shufflePosition];
      await playFromQueue(targetIndex);
      return;
    }

    if (_queueIndex - 1 >= 0) {
      await playFromQueue(_queueIndex - 1);
    }
  }

  Future<void> pause() {
    _markUserInitiatedPause();
    _setNowPlaying(
      NowPlaying(
        track: _nowPlaying.track,
        resolvedStream: _nowPlaying.resolvedStream,
        status: NowPlayingStatus.paused,
        playbackSource: _currentPlaybackSource,
      ),
    );
    return _player.pause();
  }

  Future<void> resume() {
    if (_starvationRecoveryActive && _nowPlaying.track != null) {
      final track = _nowPlaying.track!;
      AppLogger.playback(
        '[buffer-recovery] manual resume during retry — forcing fresh '
        'playVideoId() for ${track.videoId}',
      );
      return playVideoId(track.videoId, trackInfo: track);
    }

    if (_nowPlaying.track != null) {
      _setNowPlaying(
        NowPlaying(
          track: _nowPlaying.track,
          resolvedStream: _nowPlaying.resolvedStream,
          status: NowPlayingStatus.playing,
          playbackSource: _currentPlaybackSource,
        ),
      );
    }
    return _player.play();
  }

  Future<void> togglePause() {
    final goingToPause = _nowPlaying.status == NowPlayingStatus.playing;
    if (goingToPause) {
      _markUserInitiatedPause();
      if (_nowPlaying.track != null) {
        _setNowPlaying(
          NowPlaying(
            track: _nowPlaying.track,
            resolvedStream: _nowPlaying.resolvedStream,
            status: NowPlayingStatus.paused,
            playbackSource: _currentPlaybackSource,
          ),
        );
      }
      return _player.pause();
    }

    return resume();
  }

  Future<void> stop() {
    _markUserInitiatedPause();
    if (_nowPlaying.track != null) {
      _setNowPlaying(
        NowPlaying(
          track: _nowPlaying.track,
          resolvedStream: _nowPlaying.resolvedStream,
          status: NowPlayingStatus.paused,
          playbackSource: _currentPlaybackSource,
        ),
      );
    }
    return _player.stop();
  }

  /// FloatingMiniPlayer swipe-dismiss — playback সম্পূর্ণ বন্ধ + queue
  /// clear (শুধু pause না, `stop()`-এর থেকে আলাদা)। NowPlaying.idle-এ
  /// রিসেট হয় বলে mini-player নিজে থেকেই hide হয়ে যাবে (currentTrack
  /// null হলে UI নিজেই SizedBox.shrink() রিটার্ন করে)।
  ///
  /// Existing building-blocks reuse করা হয়েছে — নতুন player-lifecycle
  /// logic লাগেনি: `_endCurrentPlaybackSession` (interrupted outcome,
  /// dispose()-এর মতোই), `_player.stop()`, `_queueRepository.clearQueue()`
  /// (Phase 1 থেকেই বিদ্যমান)।
  Future<void> stopAndClear() async {
    _markUserInitiatedPause();

    _endCurrentPlaybackSession(
      finalPosition: _currentSessionLastKnownPosition,
      trackDuration: _nowPlaying.track?.duration,
      fallbackOutcome: PlaybackOutcome.interrupted,
    );

    _preloadManager.invalidate();
    _playRequestToken++; // চলমান কোনো resolve/recovery এখন stale হয়ে যাবে

    _queue.clear();
    _queueIndex = -1;
    _queueSource = QueueSource.unknown;
    _notifyQueueChanged();

    if (_queueRepository != null) {
      try {
        await _queueRepository.clearQueue();
      } catch (e) {
        AppLogger.error('clearQueue failed during stopAndClear', e);
      }
    }

    _setNowPlaying(NowPlaying.idle);
    await _player.stop();
  }

  Future<void> seek(Duration position) {
    if (_pendingResumePrompt != null) {
      _setResumePrompt(null);
    }
    return _player.seek(position);
  }

  // ⚠️ Phase 6 (Batch 4) — এখন থেকে সব ভলিউম-পরিবর্তন এই একটা method
  // দিয়েই যাওয়া উচিত (ducking/fade বাদে — ওরা সরাসরি _player.setVolume()
  // কল করে ইচ্ছাকৃতভাবে, কারণ ওই দুটো temporary/internal override,
  // user-facing volume state (_currentVolume) বদলানো উচিত না, নাহলে
  // duck শেষে/fade শেষে UI ভুল volume দেখাবে)।
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 100.0);
    _currentVolume = clamped;
    _isMuted = clamped == 0.0;
    _volumeController.add(clamped);
    await _player.setVolume(clamped);
  }

  /// Mute — বর্তমান volume মনে রেখে 0-এ নামায়। ইতিমধ্যে 0 হলে no-op
  /// (double-mute থেকে _volumeBeforeMute-এ ভুলভাবে 0 বসে যাওয়া এড়াতে)।
  Future<void> mute() async {
    if (_isMuted) return;
    _volumeBeforeMute = _currentVolume > 0 ? _currentVolume : 100.0;
    _currentVolume = 0.0;
    _isMuted = true;
    _volumeController.add(0.0);
    await _player.setVolume(0.0);
  }

  /// Unmute — mute করার আগের volume-এ ফিরে যায়।
  Future<void> unmute() async {
    if (!_isMuted) return;
    _isMuted = false;
    _currentVolume = _volumeBeforeMute;
    _volumeController.add(_currentVolume);
    await _player.setVolume(_currentVolume);
  }

  Future<void> toggleMute() => _isMuted ? unmute() : mute();

  Future<void> dispose() async {
    _disposed = true;
    _cancelSleepTimerInternal(resetState: false);

    _endCurrentPlaybackSession(
      finalPosition: _currentSessionLastKnownPosition,
      trackDuration: _nowPlaying.track?.duration,
      fallbackOutcome: PlaybackOutcome.interrupted,
    );

    await _audioFocusSub?.cancel();
    await _completedSub?.cancel();
    await _positionSub?.cancel();
    await _bufferHealthMonitor.dispose();
    await _nowPlayingController.close();
    await _playbackErrorController.close();
    await _queueController.close();
    await _resumePromptController.close();
    await _shuffleEnabledController.close();
    await _repeatModeController.close();
    await _playbackSpeedController.close();
    await _sleepTimerController.close();
    await _isResolvingController.close();
    await _volumeController.close();
    await _player.dispose();
    await _engine.dispose();
  }
}