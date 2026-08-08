import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env_config.dart';
import 'core/error/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_extension.dart';
import 'providers/album_accent_provider.dart';
import 'providers/app_router.dart';
import 'providers/playback_engine_provider.dart';
import 'providers/cache_service_provider.dart';
import 'providers/theme_provider.dart';
import 'services/performance_service.dart';

// এই ফাইলে সব platform-common bootstrap logic থাকে
// (ErrorHandler, MediaKit init, EnvConfig, Supabase init) এবং
// TeloPlayApp root widget। AudioService.init() এখানে নেই —
// সেটা শুধু main_android.dart-এ থাকবে, কারণ audio_service প্যাকেজ
// Windows-এ officially সাপোর্টেড না।
//
// এই ফাইলটা কখনো সরাসরি entry point হিসেবে রান হবে না।
// এটা শুধু main_android.dart এবং main_windows.dart থেকে import হয়।

/// Common bootstrap: ErrorHandler, MediaKit, EnvConfig, Supabase,
/// PerformanceService — platform-নির্বিশেষে যা সব প্ল্যাটফর্মেই লাগবে।
Future<void> bootstrapCommon() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorHandler.init();

  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  await EnvConfig.load();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );

  // ⚠️ Phase 1 (Smart Performance Foundation) — অন্য সব bootstrap
  // step-এর পরে, sync এবং cheap (WidgetsBindingObserver register +
  // একটা RSS sample + periodic timer শুরু করা মাত্র) — app startup
  // latency-তে কোনো লক্ষণীয় প্রভাব ফেলবে না। ইচ্ছাকৃতভাবে সবার শেষে,
  // যাতে core bootstrap (Supabase/EnvConfig) কোনোভাবে ব্যাহত না হয়
  // যদি ভবিষ্যতে এই service-এ কিছু ভারী যোগ হয়।
  PerformanceService.instance.initialize();

  // এখানে আর কোনো audio_service সম্পর্কিত কোড থাকবে না।
}

/// ⚠️ Windows/Desktop mouse-drag horizontal scroll fix।
///
/// সমস্যা: Flutter-এর default `ScrollBehavior` শুধু
/// `PointerDeviceKind.touch` (এবং stylus/trackpad আংশিকভাবে) দিয়ে drag
/// allow করে — `PointerDeviceKind.mouse` ইচ্ছাকৃতভাবে বাদ, কারণ desktop-এ
/// সাধারণত mouse দিয়ে drag করলে text-selection/click-এর সাথে conflict
/// হতে পারে ধরে নেওয়া হয়। কিন্তু আমাদের horizontal track-row-গুলোতে
/// (Recently Played, Favorites) touch/finger নেই — Windows build-এ mouse
/// দিয়েই scroll করতে হবে, তাই এই override ছাড়া list ডান দিকে scroll করা
/// যাচ্ছিল না।
///
/// Fix: `dragDevices`-এ `PointerDeviceKind.mouse` (ও `trackpad`, ভবিষ্যতে
/// touchpad-laptop ব্যবহারকারীদের জন্য) যোগ করা হলো — touch অপরিবর্তিত
/// রাখা হয়েছে যাতে Android-এ আগের মতোই কাজ করে।
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class TeloPlayApp extends ConsumerStatefulWidget {
  const TeloPlayApp({super.key});

  @override
  ConsumerState<TeloPlayApp> createState() => _TeloPlayAppState();
}

class _TeloPlayAppState extends ConsumerState<TeloPlayApp> {
  @override
  void initState() {
    super.initState();

    // ⚠️ Windows-only fire-and-forget Innertube daemon warm-up।
    //
    // InnertubeWindowsPlaybackEngine lazily initialize হয় (প্রথম
    // search()/resolveStream() কলে) — অর্থাৎ ব্যবহারকারী app খোলার পর
    // প্রথম search করলে তখনই JVM daemon spawn হয় ও warm-up cost
    // (daemon startup + JIT + connection handshake) সেই মুহূর্তে লাগে।
    //
    // এখানে app-এর প্রথম frame render হওয়ার সাথে সাথেই (postFrameCallback,
    // UI blocking না করে) সেই একই initialize() আগে থেকে ট্রিগার করা
    // হচ্ছে — যাতে ব্যবহারকারী প্রথমবার search করার আগেই daemon "গরম"
    // হয়ে বসে থাকে, এবং প্রথম search থেকেই দ্রুত ফলাফল পাওয়া যায়।
    //
    // Fire-and-forget: এখানে কোনো await/UI-blocking নেই, এবং fail হলেও
    // silently log করা হচ্ছে — কারণ initialize() নিজেই আবার lazily
    // retry হবে যখন real search/resolveStream কল আসবে (playback flow
    // কখনো এই warm-up-এর উপর নির্ভরশীল না, শুধু speed optimization)।
    if (!kIsWeb && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final engine = ref.read(playbackEngineProvider);
        engine.initialize().then((_) {
          AppLogger.playback('Innertube Windows daemon warm-up সম্পন্ন (app startup)');
        }).catchError((Object e, StackTrace st) {
          // silent — real search/resolveStream কলে lazy init আবার try করবে
          AppLogger.error('Innertube Windows daemon warm-up ব্যর্থ (non-fatal)', e);
        });
      });
    }

    // ⚠️ Phase 3 (Smart Cache) — CacheService bootstrap। platform-agnostic
    // (Android + Windows দুটোতেই দরকার, তাই Windows-only ব্লকের বাইরে,
    // Innertube warm-up-এর মতো `Platform.isWindows` গার্ড নেই)।
    //
    // `postFrameCallback` ব্যবহার করা হচ্ছে (সরাসরি initState()-এ না)
    // — Innertube warm-up-এর একই কনভেনশন অনুসরণ করে, যাতে UI-এর প্রথম
    // frame render হতে block না হয়। fire-and-forget: initialize()
    // ব্যর্থ হলেও app চলবে, শুধু cache miss-only mode-এ থাকবে (প্রতিটা
    // playVideoId() network resolve করবে, কোনো cache-hit শর্টকাট
    // পাবে না) — non-fatal, silently log হয়।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cacheService = ref.read(cacheServiceProvider);
      cacheService.initialize().then((_) {
        AppLogger.performance('CacheService warm-up সম্পন্ন (app startup)');
      }).catchError((Object e, StackTrace st) {
        AppLogger.error('CacheService warm-up ব্যর্থ (non-fatal)', e);
      });
    });
  }

  @override
  void dispose() {
    // ⚠️ Phase 1 (Smart Performance Foundation) — app root widget
    // dispose হওয়ার সময় (practically app বন্ধ হওয়ার সময়) observer
    // cleanup করা, যাতে hot-restart/test পরিবেশে duplicate observer
    // register না হয়ে যায়।
    PerformanceService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // ⚠️ Phase 6 (Smart Player UI & Theme Polish) — আগে static
    // `AppTheme.dark` ছিল, এখন `themeModeProvider` watch করে
    // Dark/AMOLED-এর মধ্যে runtime-এ switch করা যায় (Settings screen
    // থেকে `ref.read(themeModeProvider.notifier).toggle()` বা
    // `.setMode(...)` কল করলেই পুরো app rebuild হয়ে নতুন থিম নেয়)।
    final themeMode = ref.watch(themeModeProvider);

    // ⚠️ Phase 6 — album accent injection। `albumAccentProvider` state
    // বদলালে (নতুন track resolve হলে) এখানে watch করার কারণে পুরো
    // MaterialApp rebuild হয়, নতুন `AuroraColors.albumAccent`-সহ থিম
    // তৈরি হয় — ফলে `context.aurora.albumAccent`/`effectiveAccent`
    // ব্যবহার করা যেকোনো widget (glow, progress bar, mini-player)
    // স্বয়ংক্রিয়ভাবে নতুন রং পায়, কোনো আলাদা listener ছাড়াই।
    final albumAccent = ref.watch(albumAccentProvider).accentColor;
    final themeData = AppTheme.themeFor(themeMode);
    final auroraWithAccent = themeData
        .extension<AuroraColors>()!
        .copyWith(albumAccent: albumAccent, clearAlbumAccent: albumAccent == null);

    return MaterialApp.router(
      title: 'TeloPlay',
      debugShowCheckedModeBanner: false,
      theme: themeData.copyWith(extensions: [auroraWithAccent]),
      scrollBehavior: AppScrollBehavior(),
      routerConfig: router,
    );
  }
}