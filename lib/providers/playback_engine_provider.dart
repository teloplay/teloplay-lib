import '../core/platform/platform_info.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/android_playback_engine.dart';
import '../core/playback/playback_engine.dart';
import '../core/playback/web_playback_engine.dart';
import '../core/playback/innertube_windows_playback_engine.dart';

final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  final PlaybackEngine engine;

  if (kIsWeb) {
    engine = WebPlaybackEngine();
  } else if (PlatformInfo.isWindows) {
    engine = InnertubeWindowsPlaybackEngine();
  } else if (PlatformInfo.isAndroid) {
    engine = AndroidPlaybackEngine();
  } else {
    throw UnsupportedError(
      'TeloPlay: no playback engine for this platform',
    );
  }

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});