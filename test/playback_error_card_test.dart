import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/models/now_playing_model.dart';
import 'package:teloplay/widgets/player/playback_error_card.dart';

/// P0-12: the error card is pure (error in, UI out) — pumped directly,
/// no providers, no repository. Wiring (provider → card → playVideoId)
/// is covered by manual QA; the card contract is pinned here.
void main() {
  Widget cardOf(PlaybackError error, {bool retried = false, void Function()? onRetry}) {
    return MaterialApp(
      home: Scaffold(
        body: PlaybackErrorCard(
          error: error,
          onRetry: onRetry ?? () {},
        ),
      ),
    );
  }

  group('PlaybackErrorCard', () {
    testWidgets('shows the curated message (never raw cause)', (tester) async {
      await tester.pumpWidget(cardOf(
        PlaybackError(
          'No connection. Check your network and retry.',
          kind: PlaybackErrorKind.network,
          cause: Exception('SocketException: OS Error: refused'),
        ),
      ));

      expect(
        find.text('No connection. Check your network and retry.'),
        findsOneWidget,
      );
      expect(find.textContaining('SocketException'), findsNothing);
    });

    testWidgets('retryable errors show Retry and invoke onRetry', (tester) async {
      var retried = false;
      await tester.pumpWidget(cardOf(
        const PlaybackError('Unable to play this song.'),
        onRetry: () => retried = true,
      ));

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('unavailable errors hide Retry', (tester) async {
      await tester.pumpWidget(cardOf(
        const PlaybackError(
          'This track is unavailable.',
          kind: PlaybackErrorKind.unavailable,
          retryable: false,
        ),
      ));

      expect(find.text('This track is unavailable.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('kind selects icon', (tester) async {
      await tester.pumpWidget(cardOf(
        const PlaybackError('x', kind: PlaybackErrorKind.network),
      ));
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      await tester.pumpWidget(cardOf(
        const PlaybackError('x', kind: PlaybackErrorKind.unavailable),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    });
  });
}
