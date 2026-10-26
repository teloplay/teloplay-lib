import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teloplay/models/history_entry_model.dart';
import 'package:teloplay/providers/library_provider.dart';
import 'package:teloplay/screens/home/widgets/quick_access_section.dart';
import 'package:teloplay/screens/home/widgets/smart_welcome_header.dart';
import 'package:teloplay/screens/library/library_bento_screen.dart';
import 'package:teloplay/screens/library/most_played_screen.dart';
import 'package:teloplay/screens/library/recently_played_screen.dart';
import 'package:teloplay/screens/profile/widgets/about_section.dart';

/// Gate 0 — route cleanup + ComingSoon cleanup pins.
///
/// D4: `/library/offline/cached` route deleted; both "Cached Songs" tiles
/// must land on the canonical `/library/offline/downloaded` destination.
/// Credits: "Open source credits" must open the standard license page
/// (same as Licenses), not a ComingSoon snackbar.
///
/// Router-object assertions are impossible headless (appRouter build
/// subscribes to Supabase auth); debug-guard + route-absence are verified
/// by static grep in the Gate 0 report. These tests pin behavior.
void main() {
  GoRouter routerWith(Widget start) => GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(path: '/start', builder: (c, s) => start),
          GoRoute(
            path: '/library/offline/downloaded',
            builder: (c, s) => const Text('downloaded-page'),
          ),
        ],
      );

  Widget appWith(GoRouter router) =>
      MaterialApp.router(routerConfig: router);

  group('D4 cached callers resolve to downloaded', () {
    // Batch D (D3) removed both duplicate "Cached Songs" tiles (they
    // shared one destination, implying two storage systems). These pins
    // now assert: no duplicate tile exists, and the remaining canonical
    // tiles land on downloaded.
    testWidgets('bento has no duplicate Cached Songs tile', (tester) async {
      await tester.pumpWidget(
        appWith(routerWith(const LibraryBentoScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cached Songs'), findsNothing);
      // Last grid row starts offscreen in the test viewport.
      await tester.scrollUntilVisible(find.text('Offline'), 200);
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('bento Offline lands on downloaded', (tester) async {
      await tester.pumpWidget(
        appWith(routerWith(const LibraryBentoScreen())),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Offline'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offline'));
      await tester.pumpAndSettle();

      expect(find.text('downloaded-page'), findsOneWidget);
    });

    testWidgets('quick-access has no duplicate Cached Songs tile',
        (tester) async {
      await tester.pumpWidget(
        appWith(routerWith(const Scaffold(body: QuickAccessSection()))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cached Songs'), findsNothing);
      expect(find.text('Downloaded'), findsOneWidget);
    });

    testWidgets('quick-access Downloaded lands on downloaded',
        (tester) async {
      await tester.pumpWidget(
        appWith(routerWith(const Scaffold(body: QuickAccessSection()))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Downloaded'));
      await tester.pumpAndSettle();

      expect(find.text('downloaded-page'), findsOneWidget);
    });

    // Batch A (A5) — formerly-dead bare '/library/offline' pushes now
    // resolve to the canonical downloaded destination.
    testWidgets('header Offline pill lands on downloaded', (tester) async {
      await tester.pumpWidget(
        appWith(routerWith(const Scaffold(body: SmartWelcomeHeader()))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.offline_pin_rounded));
      await tester.pumpAndSettle();

      expect(find.text('downloaded-page'), findsOneWidget);
    });
  });

  group('credits action', () {
    testWidgets('Open source credits opens LicensePage', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSection())),
      );

      await tester.tap(find.text('Open source credits'));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });
  });

  // Batch A (A7) — dead sort controls removed: populated lists render
  // with no sort affordance; ordering semantics unchanged.
  group('dead sort control removed', () {
    List<RecentlyPlayedEntry> entries() => [
          RecentlyPlayedEntry(
            songId: 'v1',
            title: 'Song',
            author: 'Author',
            thumbnail: '',
            lastPlayedAt: DateTime(2026, 1, 1),
          ),
        ];

    testWidgets('Recently Played shows no sort button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentlyPlayedProvider.overrideWith(
              (ref) => Future.value(entries()),
            ),
          ],
          child: appWith(routerWith(const RecentlyPlayedScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song'), findsOneWidget);
      expect(find.byIcon(Icons.sort_rounded), findsNothing);
    });

    testWidgets('Most Played shows no sort button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mostPlayedProvider.overrideWith(
              (ref) => Future.value(entries()),
            ),
          ],
          child: appWith(routerWith(const MostPlayedScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song'), findsOneWidget);
      expect(find.byIcon(Icons.sort_rounded), findsNothing);
    });
  });
}
