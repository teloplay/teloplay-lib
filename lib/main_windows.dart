// lib/main_windows.dart
//
// Entry point for Windows. This file has no audio_service package imports
// or calls — so Windows CMake build will never even touch audio_service's
// native/platform resolution.
//
// On Windows, background/media-key control will be handled by your existing
// WindowsMediaService (lib/core/audio/windows_media_service.dart, wrapping
// smtc_windows), which is already initialized in music_player_provider.dart
// via platform-branch — no separate call needed in this file.
//
// Run/build commands:
//   flutter run -d windows -t lib/main_windows.dart
//   flutter build windows -t lib/main_windows.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/window/window_tray_manager.dart';
import 'main_common.dart';

void main() async {
  await bootstrapCommon();

  // Note: No AudioService.init() call here and no audio_service import.
  // WindowsMediaService is initialized inside music_player_provider.dart
  // via platform-branch (per your existing design, no changes needed in that file).

  // ⚠️ New: close(X) button will minimize to tray instead of exiting
  // (Spotify-style). This is initialized before runApp() because
  // window_manager.waitUntilReadyToShow() itself handles showing the window —
  // so even if runApp() is called later, the widget tree will render
  // in the visible window at the right time.
  await WindowTrayManager.instance.initialize();

  runApp(
    const ProviderScope(
      child: TeloPlayApp(),
    ),
  );
}
