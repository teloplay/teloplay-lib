import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teloplay/models/history_entry_model.dart';
import 'package:teloplay/providers/library_provider.dart';
import 'package:teloplay/screens/library/downloaded_songs_screen.dart';

/// P0-09/P0-10: dead CTAs must land on working destinations.
/// Downloaded empty CTA previously crashed (`pushNamed` with zero named
/// routes); onboarding CTAs pointed at unroutable bare paths.
///
/// Gate 0 (D2): /onboarding route + GettingStartedScreen removed, so the
/// onboarding CTA group is deleted with it (nothing left to tap).
/// Remaining coverage pins the downloaded empty CTA destination.
///
/// NOTE (test realism): Supabase singletons can't init headless, so screens
/// are pumped with provider overrides instead of the real DB graph —
/// cached songs forced empty.
/// This pins the CTA destinations, not the data layers behind them.
GoRouter _testRouter(List<GoRoute> routes, String start) =>
    GoRouter(initialLocation: start, routes: routes);

List<GoRoute> _routes(Widget home) => [
      GoRoute(path: '/home', builder: (c, s) => home),
      GoRoute(
        path: '/settings',
        builder: (c, s) => const Text('settings'),
      ),
      GoRoute(
        path: '/empty',
        builder: (c, s) => const DownloadedSongsScreen(),
      ),
    ];

Widget _homeTab() => Builder(
      builder: (c) => Text(
        'home-tab:${GoRouterState.of(c).uri.queryParameters['tab'] ?? 'home'}',
      ),
    );

void main() {
  group('downloaded empty CTA (P0-09)', () {
    testWidgets('Browse songs opens search (no crash)', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cachedSongsProvider.overrideWith(
            (ref) => Future.value(<CachedSongEntry>[]),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: _testRouter(_routes(_homeTab()), '/empty'),
        ),
      ));
      await tester.pumpAndSettle();

      // Forced-empty library → empty state with CTA (previously pushNamed).
      await tester.tap(find.text('Browse songs'));
      await tester.pumpAndSettle();

      expect(find.text('home-tab:search'), findsOneWidget);
    });
  });
}
