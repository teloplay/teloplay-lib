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
import 'providers/discovery_provider.dart' show discoveryQueueProvider;
import 'providers/playback_engine_provider.dart';
import 'providers/cache_service_provider.dart';
import 'providers/theme_provider.dart';
import 'services/performance_service.dart';

/// Common bootstrap: ErrorHandler, MediaKit, EnvConfig, Supabase,
/// PerformanceService — platform-agnostic.
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

  PerformanceService.instance.initialize();
}

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

    // Windows-only Innertube daemon warm-up
    if (!kIsWeb && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final engine = ref.read(playbackEngineProvider);
        engine.initialize().then((_) {
          AppLogger.playback('Innertube Windows daemon warm-up complete');
        }).catchError((Object e, StackTrace st) {
          AppLogger.error('Innertube Windows daemon warm-up failed (non-fatal)', e);
        });
      });
    }

    // CacheService bootstrap
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cacheService = ref.read(cacheServiceProvider);
      cacheService.initialize().then((_) {
        AppLogger.performance('CacheService warm-up complete');
      }).catchError((Object e, StackTrace st) {
        AppLogger.error('CacheService warm-up failed (non-fatal)', e);
      });
    });

    // v11 — DiscoveryQueue bootstrap. Fire-and-forget: start()
    // is idempotent. Runs in background, never blocks UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final discoveryQueue = ref.read(discoveryQueueProvider);
      discoveryQueue.start();
      AppLogger.discovery('DiscoveryQueue started (app startup)');
    });
  }

  @override
  void dispose() {
    PerformanceService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
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