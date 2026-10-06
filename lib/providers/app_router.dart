import '../core/platform/platform_info.dart';
import '../core/playback/playback_engine.dart';

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
import '../screens/library/downloaded_songs_screen.dart';
import '../screens/library/favorites_screen.dart';
import '../screens/library/history_screen.dart';
import '../screens/library/playlist_detail_screen.dart';
import '../screens/library/playlists_screen.dart';
import '../screens/library/statistics_screen.dart';

import '../screens/library/recently_played_screen.dart';
import '../screens/library/most_played_screen.dart';
import '../screens/player/player_test_screen.dart';
import '../screens/search/search_category_results_screen.dart';
import '../screens/settings/cache_settings_section.dart';
import '../screens/settings/settings_screen.dart';
import 'search_provider.dart' show SearchCategory;
import '../screens/song/song_details_screen.dart';
import '../screens/album/album_details_screen.dart';
import '../screens/artist/artist_page_screen.dart';
import '../ui/shell/platform_shell.dart';
import '../ui/shell/desktop_shell.dart';
import '../ui/shell/desktop_content_frame.dart';
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
CustomTransitionPage _platformAwarePage({
  required Widget child,
  required LocalKey key,
}) {
  final perf = PerformanceService.instance;
  final reduceEffects = perf.isReduceMotionEnabled ||
      perf.isBatterySaverUiMode ||
      perf.isLowRamMode;

  if (reduceEffects) {
    return CustomTransitionPage(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (context, animation, secondaryAnimation, c) =>
          FadeTransition(opacity: animation, child: c),
    );
  }

  final isDesktop = !kIsWeb &&
      (PlatformInfo.isWindows || PlatformInfo.isLinux || PlatformInfo.isMacOS);

  if (isDesktop) {
    // Windows/Desktop — FadeTransition + ScaleTransition, 180–220ms
    return CustomTransitionPage(
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
  return CustomTransitionPage(
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

/// P0-03…P0-07 — pure route helpers, unit-tested without widgets.
/// Shell tab order must match MobileShell/DesktopShell `_bodies` order.
const shellTabNames = ['home', 'search', 'library', 'profile'];

/// `?tab=` → tab index. Unknown/absent → 0 (home). Never throws.
int shellTabIndexForParam(String? tab) {
  if (tab == null) return 0;
  final index = shellTabNames.indexOf(tab);
  return index >= 0 ? index : 0;
}

/// See-All destination. The `/search/category` builder reads queryParameters
/// (not `extra`), so both values travel in the URL (P0-04).
String seeAllLocation(String query, SearchCategory category) {
  return '/search/category?q=${Uri.encodeComponent(query)}&category=${category.name}';
}

/// In-memory song context from a push `extra`. Bare deep links carry null
/// (or foreign extras) → null, and the screen resolves locally (P0-05).
SearchResult? songTrackFromExtra(Object? extra) {
  return extra is SearchResult ? extra : null;
}

/// Tab-navigation only — quick fade, no full route animation
/// (per requirement: "Tab Navigation: Quick Fade Only").
CustomTransitionPage _tabFadePage({
  required Widget child,
  required LocalKey key,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 100),
    transitionsBuilder: (context, animation, secondaryAnimation, c) =>
        FadeTransition(opacity: animation, child: c),
  );
}

/// Desktop/web: detail screens stay in the middle pane (sidebar + player
/// bar kept). Phones: unchanged full-screen push.
Widget _inFrame(Widget child) => DesktopContentFrame(child: child);

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

      // Root path / → redirect to /home if logged in, /welcome if not
      if (state.matchedLocation == '/') {
        return isLoggedIn ? '/home' : '/welcome';
      }

      // কোনো session না থাকলে auth route ছাড়া অন্য কোথাও যেতে দেওয়া হবে না
      if (!isLoggedIn && !isAuthRoute) {
        return '/welcome';
      }

      // Real login থাকলে auth screen-এ থাকলে home-এ পাঠাও
      if (isLoggedIn && !isGuest && isAuthRoute) {
        return '/home';
      }

      // Guest অবস্থায় /welcome-এ ফিরে গেলে home-এ পাঠাও
      if (isLoggedIn && isGuest && state.matchedLocation == '/welcome') {
        return '/home';
      }

      return null; // redirect দরকার নেই
    },
    routes: [
      // ═══════════════════════════════════════════════════════════════
      // ROOT ROUTE — redirects to /home or /welcome based on auth
      // ═══════════════════════════════════════════════════════════════
      GoRoute(
        path: '/',
        redirect: (context, state) {
          final session = Supabase.instance.client.auth.currentSession;
          return session != null ? '/home' : '/welcome';
        },
      ),
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
        pageBuilder: (context, state) {
          // P0-06/07 — tabs are ADDRESSED, not routed: `?tab=` selects the
          // shell tab without new routes or redirects. Unknown/absent tab
          // falls back to home. Explicit ValueKey forces a rebuild so the
          // shell's one-shot `initialTab` initializer re-runs on tab change.
          const tabs = shellTabNames;
          final tabIndex = shellTabIndexForParam(state.uri.queryParameters['tab']);
          final initialTab = tabIndex;
          return _tabFadePage(
            key: ValueKey('home-$initialTab'),
            child: PlatformShell(
              mobileChild: MobileShell(initialTab: initialTab),
              desktopChild: DesktopShell(initialTab: initialTab),
            ),
          );
        },
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
          child: _inFrame(const FavoritesScreen()),
        ),
      ),
      GoRoute(
        path: '/library/history',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: _inFrame(const HistoryScreen()),
        ),
      ),
      GoRoute(
        path: '/library/playlists',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: _inFrame(const PlaylistsScreen()),
        ),
      ),
      GoRoute(
        path: '/library/playlists/:id',
        pageBuilder: (context, state) {
          final playlistId = state.pathParameters['id']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: _inFrame(PlaylistDetailScreen(playlistId: playlistId)),
          );
        },
      ),

      /* ─── Legacy redirects ───────────────────────────────────────── */
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

      /* ─── Detail routes ──────────────────────────────────────────── */
      GoRoute(
        path: '/song/:id',
        pageBuilder: (context, state) {
          final songId = state.pathParameters['id']!;
          // P0-05 — forward in-memory context when the caller pushed it
          // (search results); bare deep links arrive with null extra and the
          // screen resolves from the local Songs table itself.
          final extra = state.extra;
          final track = songTrackFromExtra(extra);
          return _platformAwarePage(
            key: state.pageKey,
            child: _inFrame(SongDetailsScreen(songId: songId, track: track)),
          );
        },
      ),
      GoRoute(
        path: '/album/:id',
        pageBuilder: (context, state) {
          final albumId = state.pathParameters['id']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: _inFrame(AlbumDetailsScreen(albumId: albumId)),
          );
        },
      ),
      GoRoute(
        path: '/artist/:id',
        pageBuilder: (context, state) {
          final artistId = state.pathParameters['id']!;
          return _platformAwarePage(
            key: state.pageKey,
            child: _inFrame(ArtistPageScreen(artistId: artistId)),
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
        path: '/library/statistics',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: _inFrame(const StatisticsScreen()),
        ),
      ),
      GoRoute(
        path: '/library/recent',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: _inFrame(const RecentlyPlayedScreen()),
        ),
      ),
      GoRoute(
        path: '/library/most',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: _inFrame(const MostPlayedScreen()),
        ),
      ),
      GoRoute(
        path: '/library/most-played',
        redirect: (context, state) => '/library/most',
      ),

      GoRoute(
        path: '/library/offline/downloaded',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: _inFrame(const DownloadedSongsScreen()),
        ),
      ),
      // ⚠️ Must stay LAST among the /library routes. A parameter route
      // matches anything, so declared above the specific ones it swallows
      // /library/offline/* and nothing below it is ever reached.
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
        path: '/settings',
        pageBuilder: (context, state) => _platformAwarePage(
          key: state.pageKey,
          child: _inFrame(const SettingsScreen()),
        ),
      ),
      GoRoute(
        path: '/search/category',
        pageBuilder: (context, state) {
          final query = state.uri.queryParameters['q'] ?? '';
          final categoryName = state.uri.queryParameters['category'];
          final category = SearchCategory.values.firstWhere(
            (c) => c.name == categoryName,
            orElse: () => SearchCategory.songs,
          );
          return _platformAwarePage(
            key: state.pageKey,
            child: _inFrame(SearchCategoryResultsScreen(query: query, category: category)),
          );
        },
      ),
      // Gate 0 (D5) — debug screens exist in debug builds only and
      // follow the standard auth guards above like every other route.
      if (kDebugMode) ...[
        GoRoute(
          path: '/debug/player-test',
          builder: (context, state) => const PlayerTestScreen(),
        ),
        GoRoute(
          path: '/debug/cache-settings',
          builder: (context, state) => const CacheSettingsDebugScreen(),
        ),
      ],
    ],
  );
}