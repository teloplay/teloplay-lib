import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../logging/app_logger.dart';
import '../playback/playback_engine.dart';

/// Browser Media Session — iOS Safari lock screen / Control Center / AirPods.
class WebMediaSession {
  WebMediaSession({
    required this.onPlay,
    required this.onPause,
    this.onNext,
    this.onPrevious,
  });

  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;

  bool _bound = false;

  void bind() {
    if (_bound) return;
    final session = web.window.navigator.mediaSession;
    session.setActionHandler(
      'play',
      (() {
        onPlay();
      }).toJS,
    );
    session.setActionHandler(
      'pause',
      (() {
        onPause();
      }).toJS,
    );
    if (onNext != null) {
      session.setActionHandler(
        'nexttrack',
        (() {
          onNext!();
        }).toJS,
      );
    }
    if (onPrevious != null) {
      session.setActionHandler(
        'previoustrack',
        (() {
          onPrevious!();
        }).toJS,
      );
    }
    _bound = true;
    AppLogger.playback('[web-media-session] bound (Safari lock screen ready)');
  }

  void updateMetadata(SearchResult track) {
    final artwork = [
      web.MediaImage(src: track.thumbnail)
        ..sizes = '512x512'
        ..type = 'image/jpeg',
    ];
    web.window.navigator.mediaSession.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: track.title,
        artist: track.author,
        album: 'TeloPlay',
        artwork: artwork.toJS,
      ),
    );
  }

  void setPlaybackState(bool playing) {
    web.window.navigator.mediaSession.playbackState =
        playing ? 'playing' : 'paused';
  }

  void updatePosition({
    required Duration position,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) return;
    web.window.navigator.mediaSession.setPositionState(
      web.MediaPositionState(
        duration: duration.inMilliseconds / 1000.0,
        playbackRate: 1.0,
        position: position.inMilliseconds / 1000.0,
      ),
    );
  }
}
