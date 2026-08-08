import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/android_playback_engine.dart';
import '../core/playback/playback_engine.dart';
import '../core/playback/windows_playback_engine.dart';
import '../core/playback/innertube_windows_playback_engine.dart'; // ← নতুন import

final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  final PlaybackEngine engine;

  if (Platform.isWindows) {
    engine = InnertubeWindowsPlaybackEngine(); // ← এই লাইনটা বদলাও (আগে ছিল WindowsPlaybackEngine())
  } else if (Platform.isAndroid) {
    engine = AndroidPlaybackEngine();
  } else {
    throw UnsupportedError(
      'TeloPlay এই platform সাপোর্ট করে না: ${Platform.operatingSystem}',
    );
  }

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});