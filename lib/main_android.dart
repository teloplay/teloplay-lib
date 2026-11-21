// lib/main_android.dart
//
// Entry point for Android. Only this file calls AudioService.init(),
// because the audio_service package is not officially supported on Windows
// (audio_service only supports Android, iOS, web, Linux).
//
// By keeping separate entry points, Windows builds will never compile this file,
// so audio_service's CMake/native resolution issues won't affect Windows builds.
//
// Run/build commands:
//   flutter run -t lib/main_android.dart
//   flutter build apk -t lib/main_android.dart
//   flutter build appbundle -t lib/main_android.dart

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/telo_play_audio_handler.dart';
import 'core/audio/audio_handler_registry.dart';
import 'main_common.dart';

void main() async {
  await bootstrapCommon();

  // ⚠️ Change: AudioService.init() is no longer called before runApp().
  // Reason: Despite having correct manifest, MainActivity (FlutterFragmentActivity),
  // and super.configureFlutterEngine(), we were getting "Activity class declared
  // in AndroidManifest.xml is wrong" crash. Root cause: AudioService.init()'s
  // MethodChannel call was reaching platform-side before Activity/FlutterEngine
  // was fully attached (race condition), causing platform to misleadingly throw
  // this error. This is more common in multi-entry-point (main_android.dart)
  // setups because Activity lifecycle starts slightly differently than the
  // normal single-main.dart flow.
  //
  // Fix: First call runApp(), then call AudioService.init() after the first
  // frame is rendered (postFrameCallback) via WidgetsBinding — by then Activity
  // is fully created and FlutterEngine is attached for certain.
  runApp(
    const ProviderScope(
      child: TeloPlayApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      globalAudioHandler = await AudioService.init(
        builder: () => TeloPlayAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.teloplay.app.channel.audio',
          androidNotificationChannelName: 'TeloPlay playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (e, st) {
      debugPrint('AudioService.init() failed: $e\n$st');
    } finally {
      // ⚠️ Bug fix — complete() is called in both success and failure cases
      // (in finally block), so that even if AudioService.init() fails,
      // AndroidPlaybackEngine doesn't wait forever stuck —
      // on failure, at least the engine can attempt to configure the session
      // on its own (graceful degradation).
      if (!audioServiceReady.isCompleted) {
        audioServiceReady.complete();
      }
    }
  });
}