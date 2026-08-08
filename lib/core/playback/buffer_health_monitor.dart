import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../logging/app_logger.dart';
import '../../models/buffer_state_model.dart';

class BufferHealthMonitor {
  final Player _player;

  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _positionSub;

  final _stateController = StreamController<BufferState>.broadcast();
  Stream<BufferState> get stateStream => _stateController.stream;

  BufferState _state = BufferState.initial;
  BufferState get state => _state;

  DateTime? _stallStartedAt;
  final List<Duration> _recentStallDurations = [];
  static const _maxRollingSamples = 5;

  bool _hasPlaybackPositionAdvanced = false;

  // ⚠️ False-completion guard (bug fix) — external consumer
  // (MusicPlayerRepository-এর `_completedSub` listener) এখন এই দুটো
  // getter দিয়ে চেক করে media_kit-এর `stream.completed=true` event
  // আসলেই genuine track-completion, নাকি offline/poor-network stall-কে
  // ভুলভাবে completion হিসেবে fire করেছে।
  bool get isCurrentlyBuffering => _state.isBuffering;
  bool get hasPlaybackPositionAdvanced => _hasPlaybackPositionAdvanced;

  int _interruptionCount = 0;

  // ⚠️ Smart Recovery — stale-position bug fix।
  //
  // আগে `MusicPlayerRepository._handleBufferStarvation()` recovery শুরু
  // হওয়ার মুহূর্তে (৮s stall পার হওয়ার পরে) `_player.state.position`
  // পড়ত। কিন্তু ততক্ষণে media_kit-এর `state.position` আর নির্ভরযোগ্য
  // থাকে না — দীর্ঘ buffering/stall চলাকালীন এটা drift করে বা
  // `_player.stop()` কল হওয়ার পরে 0-তে reset হয়ে যায়। ফলে recovery
  // resume ভুল (প্রায়ই track-শুরুর) position-এ seek করত — user-এর কাছে
  // মনে হতো "গান আবার শুরু থেকে বাজছে"।
  //
  // Fix: position টা এখন stall **শুরু হওয়ার মুহূর্তেই** (buffering
  // true হওয়ার সাথে সাথে) snapshot নিয়ে রাখা হচ্ছে
  // (`_lastKnownGoodPosition`), starvation callback fire হওয়ার সময় না।
  // এই মুহূর্তে position এখনও নির্ভরযোগ্য, কারণ playback তখনো সবেমাত্র
  // stall-এ ঢুকেছে। `onBufferStarvation` callback এখন এই snapshot-টাই
  // parameter হিসেবে পাঠায়, repository আর নিজে থেকে `_player.state.position`
  // পড়ে না।
  Duration _lastKnownGoodPosition = Duration.zero;

  static const _starvationThreshold = Duration(seconds: 8);
  Timer? _starvationTimer;
  void Function(Duration lastKnownPosition)? onBufferStarvation;

  BufferHealthMonitor(this._player);

  void start() {
    _bufferingSub = _player.stream.buffering.listen(_onBufferingChanged);
    _positionSub = _player.stream.position.listen(_onPositionChanged);
  }

  void _onBufferingChanged(bool isBuffering) {
    _emit(_state.copyWith(isBuffering: isBuffering));

    if (isBuffering) {
      _stallStartedAt = DateTime.now();
      // ⚠️ stall শুরু হওয়ার মুহূর্তেই position snapshot — দেখুন উপরের
      // class-level নোট।
      _lastKnownGoodPosition = _player.state.position;

      if (_hasPlaybackPositionAdvanced) {
        _interruptionCount++;
        _emit(_state.copyWith(interruptionCount: _interruptionCount));
        AppLogger.playback(
          '[buffer-health] rebuffering detected (count=$_interruptionCount)',
        );
      }

      _starvationTimer?.cancel();
      _starvationTimer = Timer(_starvationThreshold, () {
        AppLogger.playback(
          '[buffer-health] starvation threshold exceeded '
          '(${_starvationThreshold.inSeconds}s) — triggering recovery hook '
          '(snapshot position=$_lastKnownGoodPosition)',
        );
        onBufferStarvation?.call(_lastKnownGoodPosition);
      });
    } else {
      _starvationTimer?.cancel();
      _starvationTimer = null;

      if (_hasPlaybackPositionAdvanced && _stallStartedAt != null) {
        final stallDuration = DateTime.now().difference(_stallStartedAt!);
        _recordStallSample(stallDuration);
      }

      _stallStartedAt = null;
    }
  }

  void _recordStallSample(Duration stallDuration) {
    _recentStallDurations.add(stallDuration);
    if (_recentStallDurations.length > _maxRollingSamples) {
      _recentStallDurations.removeAt(0);
    }

    final avgMs = _recentStallDurations
            .map((d) => d.inMilliseconds)
            .reduce((a, b) => a + b) /
        _recentStallDurations.length;

    final quality = switch (avgMs) {
      < 500 => NetworkQuality.good,
      < 2000 => NetworkQuality.moderate,
      _ => NetworkQuality.poor,
    };

    _emit(_state.copyWith(networkQuality: quality));

    AppLogger.playback(
      '[buffer-health] stall=$stallDuration avg=${avgMs.toStringAsFixed(0)}ms '
      'quality=$quality',
    );
  }

  static const _positionAdvanceThreshold = Duration(milliseconds: 300);

  void _onPositionChanged(Duration position) {
    if (!_hasPlaybackPositionAdvanced &&
        position >= _positionAdvanceThreshold) {
      _hasPlaybackPositionAdvanced = true;
      AppLogger.playback(
        '[buffer-health] playback position advanced ($position) — '
        'rebuffering detection now active',
      );
    }

    // ⚠️ Stall চলাকালীন না থাকলে (অর্থাৎ playback স্বাভাবিকভাবে এগোচ্ছে)
    // position-টা নিয়মিত update রাখা হচ্ছে, যাতে পরবর্তী কোনো stall
    // শুরু হলে `_onBufferingChanged`-এ সঠিক সাম্প্রতিক position পাওয়া
    // যায় (এটা শুধুই একটা fallback safety — মূল snapshot stall-শুরুর
    // মুহূর্তেই নেওয়া হয়, কিন্তু এই সাম্প্রতিক-position tracking থাকলে
    // stall শুরুর ঠিক আগের valid position-ও নিশ্চিত থাকে)।
    if (!_state.isBuffering) {
      _lastKnownGoodPosition = position;
    }

    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
  }

  void resetForNewTrack() {
    _interruptionCount = 0;
    _recentStallDurations.clear();
    _hasPlaybackPositionAdvanced = false;
    _stallStartedAt = null;
    _lastKnownGoodPosition = Duration.zero;
    _starvationTimer?.cancel();
    _starvationTimer = null;
    _emit(BufferState.initial.copyWith(
      networkQuality: _state.networkQuality,
    ));
  }

  void _emit(BufferState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> dispose() async {
    _starvationTimer?.cancel();
    await _bufferingSub?.cancel();
    await _positionSub?.cancel();
    await _stateController.close();
  }
}