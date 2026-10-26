import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/widgets/context_menu.dart';

/// P1-L: null-callback rows hide instead of rendering dead.
/// Pure widget (theme falls back) — no providers needed.
void main() {
  Widget menuOf(ContextMenu menu) {
    return MaterialApp(home: Scaffold(body: menu));
  }

  /// Production shows the menu on a modal route (showContextMenu ->
  /// showModalBottomSheet), so row taps pop a real route. Pumping the
  /// menu directly is fine for render assertions, but tap-fire tests
  /// must open it the production way — otherwise pop() empties the root
  /// navigator history (framework assert), and a Dialog gives it
  /// unbounded height (layout explosion).
  Future<void> pumpMenuOnRoute(WidgetTester tester, ContextMenu menu) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (_) => menu,
            ),
            child: const Text('open menu'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open menu'));
    await tester.pumpAndSettle();
  }

  group('ContextMenu null-skip', () {
    testWidgets('no callbacks renders header only, zero dead rows',
        (tester) async {
      await tester.pumpWidget(menuOf(
        const ContextMenu(title: 'Song', type: ContextMenuType.song),
      ));

      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Play Next'), findsNothing);
      expect(find.text('Add To Queue'), findsNothing);
      expect(find.text('Add To Playlist'), findsNothing);
      expect(find.text('Favorite'), findsNothing);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('provided callbacks render their rows', (tester) async {
      var queued = false;
      await tester.pumpWidget(menuOf(
        ContextMenu(
          title: 'Song',
          type: ContextMenuType.song,
          onAddToQueue: () => queued = true,
          onToggleFavorite: () {},
        ),
      ));

      expect(find.text('Play Next'), findsNothing);
      expect(find.text('Add To Queue'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);

      await tester.tap(find.text('Add To Queue'));
      await tester.pumpAndSettle();
      expect(queued, isTrue);
    });

    testWidgets('downloaded variant shows Delete Download only with handler',
        (tester) async {
      await tester.pumpWidget(menuOf(
        const ContextMenu(title: 'Song', type: ContextMenuType.downloaded),
      ));
      expect(find.text('Delete Download'), findsNothing);

      await tester.pumpWidget(menuOf(
        ContextMenu(
          title: 'Song',
          type: ContextMenuType.downloaded,
          onDownload: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Delete Download'), findsOneWidget);
    });

    // Batch 5 — previously unpinned rows: each renders only with its
    // handler, fires it on tap, and stays hidden without it.
    // Render assertions use the direct harness; tap-fire goes through
    // the dialog-route harness (see note above).
    testWidgets('playlist/artist/album/share rows render with handlers',
        (tester) async {
      await tester.pumpWidget(menuOf(
        ContextMenu(
          title: 'Song',
          type: ContextMenuType.song,
          onAddToPlaylist: () {},
          onGoToArtist: () {},
          onGoToAlbum: () {},
          onShare: () {},
        ),
      ));

      expect(find.text('Add To Playlist'), findsOneWidget);
      expect(find.text('Go To Artist'), findsOneWidget);
      expect(find.text('Go To Album'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('row taps fire their handlers', (tester) async {
      var playlist = false;
      var shared = false;
      await pumpMenuOnRoute(
        tester,
        ContextMenu(
          title: 'Song',
          type: ContextMenuType.song,
          onAddToPlaylist: () => playlist = true,
          onShare: () => shared = true,
        ),
      );

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shared, isTrue);
      expect(playlist, isFalse);
    });

    testWidgets('remove rows are type-gated and handler-gated',
        (tester) async {
      // playlistTrack without handler: no remove row.
      await tester.pumpWidget(menuOf(
        const ContextMenu(title: 'Song', type: ContextMenuType.playlistTrack),
      ));
      expect(find.text('Remove from Playlist'), findsNothing);

      // playlistTrack with handler: playlist row only, not queue row.
      await tester.pumpWidget(menuOf(
        ContextMenu(
          title: 'Song',
          type: ContextMenuType.playlistTrack,
          onRemove: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Playlist'), findsOneWidget);
      expect(find.text('Remove from Queue'), findsNothing);

      // queueItem with handler: queue row only.
      await tester.pumpWidget(menuOf(
        ContextMenu(
          title: 'Song',
          type: ContextMenuType.queueItem,
          onRemove: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Queue'), findsOneWidget);
      expect(find.text('Remove from Playlist'), findsNothing);

      // song type never shows remove rows even with handler.
      await tester.pumpWidget(menuOf(
        ContextMenu(
          title: 'Song',
          type: ContextMenuType.song,
          onRemove: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Playlist'), findsNothing);
      expect(find.text('Remove from Queue'), findsNothing);
    });
  });
}
