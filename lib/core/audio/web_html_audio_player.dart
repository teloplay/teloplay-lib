import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../logging/app_logger.dart';

/// Browser-native HTMLAudioElement wrapper.
///
/// iOS Safari background + lock-screen Media Session only attach to a real
/// HTML <audio> element, not CanvasKit/mpv. This stays app-controlled so
/// later Supabase/history/queue wiring can sit on top of the same API.
class WebHtmlAudioPlayer {
  WebHtmlAudioPlayer() {
    _audio = web.HTMLAudioElement()
      ..preload = 'auto'
      ..controls = false
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true');
    web.document.body?.append(_audio);

    _playingSub = _audio.onPlay.listen((_) {
      _playing = true;
      _playingController.add(true);
    });
    _pauseSub = _audio.onPause.listen((_) {
      _playing = false;
      _playingController.add(false);
    });
    _timeSub = _audio.onTimeUpdate.listen((_) {
      _positionController.add(Duration(
        milliseconds: (_audio.currentTime * 1000).round(),
      ));
    });
    _metaSub = _audio.onDurationChange.listen((_) {
      final d = _audio.duration;
      if (d.isFinite && d > 0) {
        _durationController.add(Duration(milliseconds: (d * 1000).round()));
      }
    });
    _waitSub = _audio.onWaiting.listen((_) => _bufferingController.add(true));
    _canPlaySub =
        _audio.onCanPlay.listen((_) => _bufferingController.add(false));
    _errorSub = _audio.onError.listen((_) {
      AppLogger.playback(
          '[web-audio] element error code=${_audio.error?.code}');
    });
    _endedSub = _audio.onEnded.listen((_) {
      _playing = false;
      _playingController.add(false);
      _completedController.add(true);
    });
  }

  late final web.HTMLAudioElement _audio;

  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<bool>.broadcast();

  StreamSubscription<web.Event>? _playingSub;
  StreamSubscription<web.Event>? _pauseSub;
  StreamSubscription<web.Event>? _timeSub;
  StreamSubscription<web.Event>? _metaSub;
  StreamSubscription<web.Event>? _waitSub;
  StreamSubscription<web.Event>? _canPlaySub;
  StreamSubscription<web.Event>? _errorSub;
  StreamSubscription<web.Event>? _endedSub;

  bool _playing = false;
  bool get playing => _playing;

  Stream<bool> get playingStream => _playingController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<bool> get bufferingStream => _bufferingController.stream;
  Stream<bool> get completedStream => _completedController.stream;

  Future<void> open(String url) async {
    _audio.src = url;
    _audio.load();
  }

  Future<void> play() async {
    try {
      await _audio.play().toDart;
    } catch (e) {
      AppLogger.playback('[web-audio] play() blocked or failed: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    _audio.pause();
  }

  Future<void> stop() async {
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
    _playing = false;
    _playingController.add(false);
  }

  Future<void> seek(Duration position) async {
    _audio.currentTime = position.inMilliseconds / 1000.0;
  }

  Future<void> dispose() async {
    await stop();
    await _playingSub?.cancel();
    await _pauseSub?.cancel();
    await _timeSub?.cancel();
    await _metaSub?.cancel();
    await _waitSub?.cancel();
    await _canPlaySub?.cancel();
    await _errorSub?.cancel();
    await _endedSub?.cancel();
    _audio.remove();
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferingController.close();
    await _completedController.close();
  }
}
