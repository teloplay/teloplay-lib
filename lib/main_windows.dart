// lib/main_windows.dart
//
// Windows-এর জন্য entry point। এই ফাইলে audio_service প্যাকেজের
// কোনো import বা কল নেই — তাই Windows CMake build কখনো audio_service-এর
// native/platform resolution ছুঁয়েও দেখবে না।
//
// Windows-এ background/media-key control হবে আপনার বিদ্যমান
// WindowsMediaService (lib/core/audio/windows_media_service.dart,
// smtc_windows wrap করা) দিয়ে, যেটা music_player_provider.dart-এ
// platform-branch অনুযায়ী এমনিতেই init হয় — এই ফাইলে সেটার জন্য
// আলাদা কোনো কল লাগবে না।
//
// রান/বিল্ড করার কমান্ড:
//   flutter run -d windows -t lib/main_windows.dart
//   flutter build windows -t lib/main_windows.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/window/window_tray_manager.dart';
import 'main_common.dart';

void main() async {
  await bootstrapCommon();

  // লক্ষ্য করুন: এখানে AudioService.init() কল নেই এবং কোনো
  // audio_service import নেই। WindowsMediaService init হয়
  // music_player_provider.dart-এর ভেতরে platform-branch দিয়ে
  // (আপনার existing design অনুযায়ী, ওই ফাইলে কোনো পরিবর্তন লাগবে না)।

  // ⚠️ নতুন: close(X) বাটন চাপলে exit না হয়ে tray-তে minimize হবে
  // (Spotify-style)। এটা runApp()-এর আগে init করা হচ্ছে কারণ
  // window_manager.waitUntilReadyToShow() নিজেই window দেখানোর
  // দায়িত্ব নেয় — তাই runApp() পরে কল হলেও widget tree ঠিক সময়েই
  // দৃশ্যমান window-তে render হবে।
  await WindowTrayManager.instance.initialize();

  runApp(
    const ProviderScope(
      child: TeloPlayApp(),
    ),
  );
}