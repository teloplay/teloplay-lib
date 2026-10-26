import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/screens/home/widgets/content_rail.dart';
import 'package:teloplay/widgets/skeleton_loader.dart';

/// Batch B — Home rail states are explicit: populated / empty-guidance /
/// hidden-without-copy / loading skeleton. No providers needed (pure UI).
void main() {
  ContentRailItem item() => ContentRailItem(
        id: 'v1',
        title: 'Song',
        subtitle: 'Author',
        thumbnail: '',
        onTap: () {},
      );

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  group('ContentRail states', () {
    testWidgets('populated shows title, item and See All', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ContentRail(
        title: 'Recently Played',
        items: [item()],
        onSeeAll: () => tapped = true,
        emptyMessage: 'Empty.',
      )));

      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
      expect(find.text('See All'), findsOneWidget);

      await tester.tap(find.text('See All'));
      expect(tapped, isTrue);
    });

    testWidgets('empty with message shows guidance + browse, hides See All',
        (tester) async {
      var browsed = false;
      await tester.pumpWidget(wrap(ContentRail(
        title: 'Your Favorites',
        items: const [],
        onSeeAll: () {},
        emptyMessage: 'Songs you like will appear here.',
        onEmptyBrowse: () => browsed = true,
      )));

      expect(find.text('Your Favorites'), findsOneWidget);
      expect(find.text('Songs you like will appear here.'), findsOneWidget);
      expect(find.text('Browse songs'), findsOneWidget);
      expect(find.text('See All'), findsNothing);

      await tester.tap(find.text('Browse songs'));
      expect(browsed, isTrue);
    });

    testWidgets('empty message without browse shows no button',
        (tester) async {
      await tester.pumpWidget(wrap(const ContentRail(
        title: 'Most Played',
        items: [],
        emptyMessage: 'Keep listening.',
      )));

      expect(find.text('Keep listening.'), findsOneWidget);
      expect(find.text('Browse songs'), findsNothing);
    });

    testWidgets('empty without message stays hidden', (tester) async {
      await tester.pumpWidget(wrap(ContentRail(
        title: 'Hidden Rail',
        items: const [],
        onSeeAll: () {},
      )));

      expect(find.text('Hidden Rail'), findsNothing);
    });
  });

  group('RailLoadingPlaceholder', () {
    testWidgets('shows title and shimmer cards', (tester) async {
      await tester.pumpWidget(
        wrap(const RailLoadingPlaceholder(title: 'Recently Played')),
      );

      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.byType(SkeletonLoader), findsWidgets);
      expect(find.text('See All'), findsNothing);
    });
  });
}
