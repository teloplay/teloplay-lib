import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/performance_service.dart';
import '../providers/auth_providers.dart';
import '../screens/auth/welcome_screen.dart';
import '../screens/auth/email_input_screen.dart';
import '../screens/auth/otp_verify_screen.dart';
import '../screens/library/favorites_screen.dart';
import '../screens/library/history_screen.dart';
import '../screens/library/playlist_detail_screen.dart';
import '../screens/library/playlists_screen.dart';
import '../screens/player/player_test_screen.dart';
import '../screens/settings/cache_settings_section.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/song/song_details_screen.dart';
import '../screens/album/album_details_screen.dart';
import '../screens/artist/artist_page_screen.dart';
import '../ui/shell/platform_shell.dart';
import '../ui/shell/desktop_shell.dart';
import '../ui/shell/mobile_shell.dart';
import '../screens/home/home_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/player/now_playing_screen.dart';

part 'app_router.g.dart';


/// GoRouter-এর redirect logic Stream থেকে চলে বলে Listenable দরকার।
/// authStateChangesProvider-এর নতুন value এলেই এটা GoRouter-কে notify করবে,
/// ফলে redirect আবার evaluate হবে (login/logout হলে auto-navigate)।
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
  }
}

/// Phase 6 Batch 5 — shared page-transition builder. Respects the
/// 3 Performance-aware UI flags (low RAM / reduce motion / battery
/// saver): if any are active, falls back to an instant/near-instant
/// fade instead of the full platform-specific animation.
CustomTransitionPage<T> _platformAwarePage<T>({
  required Widget child,
  required LocalKey key,
}) {
  final perf = PerformanceService.instance;
  final reduceEffects = perf.isReduceMotionEnabled ||
      perf.isBatterySaverUiMode ||
      perf.isLowRamMode;

  if (reduceEffects) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (context, animation, secondaryAnimation, c) =>
          FadeTransition(opacity: animation, child: c),
    );
  }

  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop) {
    // Windows/Desktop — FadeTransition + ScaleTransition, 180–220ms
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, c) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.98, end: 1.0).animate(curved),
            child: c,
          ),
        );
      },
    );
  }

  // Android/mobile — SlideTransition + CurvedAnimation, 250–300ms
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, c) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
        child: c,
      );
    },
  );
}

/// Tab-navigation only — quick fade, no full route animation
/// (per requirement: "Tab Navigation: Quick Fade Only").
CustomTransitionPage<T> _tabFadePage<T>({
  required Widget child,
  required LocalKey key,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 100),
    transitionsBuilder: (context, animation, secondaryAnimation, c) =>
        FadeTransition(opacity: animation, child: c),
  );
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/welcome',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      final isGuest = session?.user.isAnonymous ?? false;
      final isAuthRoute = state.matchedLocation.startsWith('/welcome') ||
          state.matchedLocation.startsWith('/auth');

      // debug route-গুলোকে auth redirect logic সম্পূর্ণ এড়িয়ে যেতে দাও —
      // এগুলো শুধু engine/feature-testing-এর জন্য, session/login অবস্থা
      // যাই হোক না কেন সরাসরি খোলা যাবে।
      if (state.matchedLocation == '/debug/player-test' ||
          state.matchedLocation == '/debug/cache-settings') {
        return null;
      }

      // কোনো session না থাকলে (কখনো guest হিসেবেও ঢোকেনি) —
      // auth route ছাড়া অন্য কোথাও যেতে দেওয়া হবে না
      if (!isLoggedIn && !isAuthRoute) {
        return '/welcome';
      }

      // Real (non-guest) login থাকলে এবং এখনো auth screen-এ থাকলে —
      // home-এ পাঠিয়ে দাও। Guest-কে এখানে বাদ রাখা হয়েছে ইচ্ছাকৃতভাবে,
      // কারণ guest অবস্থায় email link করার জন্য /auth/email-এ যেতে
      // পারতে হবে, redirect তাকে আটকে দেবে না।
      if (isLoggedIn && !isGuest && isAuthRoute) {
        return '/home';
      }

      // Guest অবস্থায় /welcome-এ ফিরে গেলে home-এ পাঠাও
      // (কারণ guest ইতিমধ্যে "logged in" — শুধু email/otp route allow করা হচ্ছে)
      if (isLoggedIn && isGuest && state.matchedLocation == '/welcome') {
        return '/home';
      }

      return null; // redirect দরকার নেই
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/auth/email',
        builder: (context, state) => const EmailInputScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return OtpVerifyScreen(email: email);
        },
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => _tabFadePage(
          key: state.pageKey,
          child: const PlatformShell(
            mobileChild: MobileShell(),
            desktopChild: DesktopShell(),
          ),
        ),
      ),
      GoRoute(
        path: '/player',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: const NowPlayingScreen(),
        ),
      ),
      // ═══════════════════════════════════════════════════════════════
      // Phase 6.5B — Route Architecture Lock
      // ═══════════════════════════════════════════════════════════════

      /* ─── Library-unified content routes ─────────────────────────── */
      GoRoute(
        path: '/library/favorites',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: const FavoritesScreen(),
        ),
      ),
      GoRoute(
        path: '/library/history',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: const HistoryScreen(),
        ),
      ),
      GoRoute(
        path: '/library/playlists',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: const PlaylistsScreen(),
        ),
      ),
      GoRoute(
        path: '/library/playlists/:id',
        pageBuilder: (context, state) {
          final playlistId = state.pathParameters['id']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: PlaylistDetailScreen(playlistId: playlistId),
          );
        },
      ),

      /* ─── Legacy redirects — keep deep links / saved state alive ──── */
      GoRoute(
        path: '/favorites',
        redirect: (context, state) => '/library/favorites',
      ),
      GoRoute(
        path: '/history',
        redirect: (context, state) => '/library/history',
      ),
      GoRoute(
        path: '/playlists',
        redirect: (context, state) => '/library/playlists',
      ),
      GoRoute(
        path: '/playlists/:id',
        redirect: (context, state) =>
            '/library/playlists/${state.pathParameters['id']}',
      ),

      /* ─── NEW — Detail routes (Song / Album / Artist / Playlist) ──── */
      GoRoute(
        path: '/song/:id',
        pageBuilder: (context, state) {
          final songId = state.pathParameters['id']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: SongDetailsScreen(songId: songId),
          );
        },
      ),
      GoRoute(
        path: '/album/:id',
        pageBuilder: (context, state) {
          final albumId = state.pathParameters['id']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: AlbumDetailsScreen(albumId: albumId),
          );
        },
      ),
      GoRoute(
        path: '/artist/:id',
        pageBuilder: (context, state) {
          final artistId = state.pathParameters['id']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: ArtistPageScreen(artistId: artistId),
          );
        },
      ),
      GoRoute(
        path: '/playlist/:id',
        redirect: (context, state) =>
            '/library/playlists/${state.pathParameters['id']}',
      ),

      // ═══════════════════════════════════════════════════════════════
      // End Phase 6.5B
      // ═══════════════════════════════════════════════════════════════

      GoRoute(
        path: '/library/:section',
        pageBuilder: (context, state) {
          final section = state.pathParameters['section']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: PlatformShell(
              mobileChild: MobileShell(initialLibrarySection: section),
              desktopChild: DesktopShell(initialLibrarySection: section),
            ),
          );
        },
      ),
      GoRoute(
        path: '/library/offline/downloaded',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: PlatformShell(
            mobileChild: const MobileShell(initialLibrarySection: 'offline/downloaded'),
            desktopChild: const DesktopShell(initialLibrarySection: 'offline/downloaded'),
          ),
        ),
      ),
      GoRoute(
        path: '/library/offline/cached',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: PlatformShell(
            mobileChild: const MobileShell(initialLibrarySection: 'offline/cached'),
            desktopChild: const DesktopShell(initialLibrarySection: 'offline/cached'),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: const SettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/debug/player-test',
        builder: (context, state) => const PlayerTestScreen(),
      ),
      GoRoute(
        path: '/debug/cache-settings',
        builder: (context, state) => const CacheSettingsDebugScreen(),
      ),
    ],
  );
}