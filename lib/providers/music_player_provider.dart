import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_handler_registry.dart' show globalAudioHandler;
import '../core/audio/windows_media_service.dart';
import '../core/logging/app_logger.dart';
import '../core/playback/playback_engine.dart';
import '../data/repositories/music_player_repository.dart';
import '../data/repositories/queue_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../models/now_playing_model.dart';
import 'database_provider.dart';
import 'playback_engine_provider.dart';
import 'repository_providers.dart';
import 'cache_service_provider.dart';

final queueRepositoryProvider = Provider<QueueRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return QueueRepository(db);
});

// ⚠️ Phase 1 (Shuffle/Repeat/Speed/Sleep Timer) — generic key-value
// settings repository, MusicPlayerRepository-এর সাথে সাথে LibraryRepository
// (Phase 2)-ও একই provider ব্যবহার করবে theme/language ইত্যাদির জন্য।
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SettingsRepository(db);
});

/// পুরো app-এ single MusicPlayerRepository instance।
/// UI screens এটা দিয়েই play/pause/seek কল করবে।
///
/// এই provider তৈরি হওয়ার সাথে সাথেই platform-অনুযায়ী OS media
/// integration bind হয়:
///   - Android: main_android.dart-এ init করা `globalAudioHandler`-এর
///     সাথে এই repository attach করা হয় (notification/lock screen/
///     Bluetooth/media key)। যেহেতু AudioService.init() runApp()-এর
///     পরে (postFrameCallback-এ) কল হয়, এই provider build() সেটার
///     আগে চলে যেতে পারে — তাই retry loop দিয়ে handler রেডি হওয়া
///     পর্যন্ত অপেক্ষা করা হয় (নিচে দেখুন)।
///   - Windows: `WindowsMediaService` (SMTC) তৈরি করে initialize করা
///     হয় (media flyout/keyboard media key/Bluetooth), এবং
///     repository dispose হওয়ার সময় এটাও dispose হয়।
final musicPlayerRepositoryProvider = Provider<MusicPlayerRepository>((ref) {
  final engine = ref.watch(playbackEngineProvider);
  final queueRepo = ref.watch(queueRepositoryProvider);

  // ⚠️ Phase 0.9 (Foundation Hardening) — BehaviourTrackingService এখন
  // constructor-এ inject করা হচ্ছে, যাতে search()/playVideoId()-এর ভেতরের
  // capture call গুলো (completed/skipped/interrupted outcome, search
  // query) আসলে কার্যকর হয়। এই provider repository_providers.dart-এ
  // ডিফাইন করা (shared/cross-cutting, Phase 2-এ LibraryRepository-ও
  // একই instance ব্যবহার করবে)।
  final behaviourTracking = ref.watch(behaviourTrackingServiceProvider);

  // ⚠️ Phase 1 (Shuffle/Repeat/Speed/Sleep Timer) — SettingsRepository
  // constructor-এ inject করা হচ্ছে, যাতে shuffle/repeat/speed
  // app-startup-এ আগের session থেকে load হয় এবং বদলালে persist হয়।
  final settingsRepo = ref.watch(settingsRepositoryProvider);

  // ⚠️ Phase 3 (Smart Cache) — CacheService constructor-এ inject করা
  // হচ্ছে, যাতে playVideoId()-এর cache-hit check এবং current/preload
  // track caching কার্যকর হয়। `cacheServiceProvider` নিজেই এখনো
  // `CacheService.initialize()` কল করেনি এই মুহূর্তে — সেটা
  // main_common.dart-এর postFrameCallback-এ হয় (app-startup, একবারই)।
  // এখানে provider শুধু ইতিমধ্যে-initialize-হওয়া (বা হতে-যাওয়া)
  // singleton instance পাচ্ছে — `MusicPlayerRepository`-এর কোনো কল
  // `CacheService.initialize()` সম্পূর্ণ হওয়ার আগে এলে, `CacheService`-
  // এর প্রতিটা public মেথড নিজে থেকেই `_initialized` guard করে (দেখো
  // cache_service.dart) — তাই early-call race harmless (silently
  // no-op, exception না)।
  final cacheService = ref.watch(cacheServiceProvider);

  final repo = MusicPlayerRepository(
    engine,
    queueRepo,
    behaviourTracking,
    settingsRepo,
    cacheService,
  );

  // Provider তৈরি হওয়ার সাথে সাথেই আগের session-এর queue restore করার
  // চেষ্টা — fire-and-forget, কারণ Provider-এর build() sync হতে হবে।
  // restoreQueue() নিজেই সব error handle করে (crash করবে না)।
  unawaited(repo.restoreQueue());

  if (!kIsWeb && Platform.isAndroid) {
    // main_android.dart-এ AudioService.init()-এর মাধ্যমে তৈরি হওয়া handler-এর
    // সাথে এই (একমাত্র) repository bind করা — এখান থেকেই notification/
    // lock screen/Bluetooth সব repository-এর real state পাবে।
    //
    // ⚠️ টাইমিং নোট: AudioService.init() এখন main_android.dart-এ
    // runApp()-এর পরে (postFrameCallback-এ) কল হয়, কিন্তু এই provider-এর
    // build() প্রথম frame render হওয়ার আগেই চলতে পারে — তাই এখানে
    // globalAudioHandler তখনো null থাকতে পারে even though সেটা কিছুক্ষণ
    // পরেই সেট হয়ে যাবে। তাই সরাসরি null হলে দমে না গিয়ে, ছোট
    // retry loop দিয়ে অপেক্ষা করা হচ্ছে (max ৩ সেকেন্ড, ৫০ms interval) —
    // handler রেডি হওয়ামাত্রই attach হয়ে যাবে, ব্যর্থ হলে তবেই গ্রেসফুল
    // fallback log আসবে।
    unawaited(() async {
      const maxAttempts = 60; // 60 * 50ms = 3 সেকেন্ড পর্যন্ত অপেক্ষা
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final handler = globalAudioHandler;
        if (handler != null) {
          handler.attachRepository(repo);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      // ৩ সেকেন্ড পরও handler null — তখনই আসল fallback log
      AppLogger.error(
        'globalAudioHandler null on Android (৩ সেকেন্ড অপেক্ষার পরও) — '
        'background notification/lock screen controls থাকবে না',
        null,
      );
    }());
  } else if (!kIsWeb && Platform.isWindows) {
    final windowsMediaService = WindowsMediaService(repo);
    unawaited(windowsMediaService.initialize());
    ref.onDispose(() {
      unawaited(windowsMediaService.dispose());
    });
  }

  ref.onDispose(() {
    repo.dispose();
  });

  return repo;
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.playingStream;
});

final playbackPositionProvider = StreamProvider<Duration>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.positionStream;
});

final playbackDurationProvider = StreamProvider<Duration?>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.durationStream;
});

final playbackBufferingProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.bufferingStream;
});

final playbackErrorProvider = StreamProvider<String>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.errorStream;
});

final nowPlayingProvider = StreamProvider<NowPlaying>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.nowPlayingStream;
});

final currentTrackProvider = StreamProvider<SearchResult?>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.currentTrackStream;
});

final queueProvider = StreamProvider<List<SearchResult>>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.queueStream;
});

final resumePromptProvider = StreamProvider<ResumePrompt?>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.resumePromptStream;
});

// ⚠️ Phase 1 (Shuffle/Repeat/Speed/Sleep Timer)

final shuffleEnabledProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.shuffleEnabledStream;
});

final repeatModeProvider = StreamProvider<PlaybackRepeatMode>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.repeatModeStream;
});

final playbackSpeedProvider = StreamProvider<double>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.playbackSpeedStream;
});

final sleepTimerProvider = StreamProvider<SleepTimerState>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.sleepTimerStream;
});

final isResolvingProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.isResolvingStream;
});

final volumeProvider = StreamProvider<double>((ref) {
  final repo = ref.watch(musicPlayerRepositoryProvider);
  return repo.volumeStream;
});