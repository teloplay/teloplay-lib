// lib/main_android.dart
//
// Android-এর জন্য entry point। এই ফাইলেই শুধু AudioService.init() কল হয়,
// কারণ audio_service প্যাকেজ Windows-এ officially সাপোর্টেড না
// (audio_service প্যাকেজ শুধু Android, iOS, web, Linux সাপোর্ট করে)।
//
// এভাবে আলাদা entry point রাখার ফলে Windows build কখনো এই ফাইলটা
// compile করবে না, তাই audio_service-এর কোনো CMake/native resolution
// সমস্যা Windows build-এ আর আসবে না।
//
// রান/বিল্ড করার কমান্ড:
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

  // ⚠️ পরিবর্তন: AudioService.init() এখন runApp()-এর আগে কল হচ্ছে না।
  // কারণ: manifest, MainActivity (FlutterFragmentActivity), super.
  // configureFlutterEngine() — সবকিছু সঠিক থাকা সত্ত্বেও
  // "Activity class declared in AndroidManifest.xml is wrong" crash
  // হচ্ছিল। এর root cause: AudioService.init()-এর MethodChannel কল
  // Activity/FlutterEngine সম্পূর্ণ attach হওয়ার আগেই platform-side-এ
  // পৌঁছাচ্ছিল (race condition), ফলে platform misleadingly এই error
  // দিচ্ছিল। এটা multi-entry-point (main_android.dart) সেটআপে বেশি
  // দেখা যায় কারণ Activity lifecycle normal single-main.dart flow-এর
  // চেয়ে একটু ভিন্নভাবে শুরু হয়।
  //
  // ফিক্স: প্রথমে runApp() কল করা হচ্ছে, এবং AudioService.init()
  // WidgetsBinding-এর প্রথম frame render হওয়ার পরে (postFrameCallback)
  // কল করা হচ্ছে — তখন Activity সম্পূর্ণ তৈরি ও FlutterEngine attach
  // হয়ে গেছে নিশ্চিতভাবে।
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
      // ⚠️ Bug fix — সফল বা ব্যর্থ, দুই ক্ষেত্রেই complete() করা হচ্ছে
      // (finally-তে), যাতে AudioService.init() ব্যর্থ হলেও
      // AndroidPlaybackEngine চিরকাল অপেক্ষা করে আটকে না থাকে —
      // ব্যর্থ হলে অন্তত engine নিজের মতো session configure করার
      // চেষ্টা করতে পারবে (গ্রেসফুল ডিগ্রেডেশন)।
      if (!audioServiceReady.isCompleted) {
        audioServiceReady.complete();
      }
    }
  });
}