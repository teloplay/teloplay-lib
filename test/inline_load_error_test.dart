import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/widgets/inline_load_error.dart';

/// P1-A: the shared inline error row contract — message shown, Retry wired,
/// no raw error leakage. Screens pass curated messages only.
void main() {
  Widget rowOf(String message, {required VoidCallback onRetry}) {
    return MaterialApp(
      home: Scaffold(body: InlineLoadError(message: message, onRetry: onRetry)),
    );
  }

  group('InlineLoadError', () {
    testWidgets('shows message and invokes retry', (tester) async {
      var retried = false;
      await tester.pumpWidget(rowOf(
        "Couldn't load favorites",
        onRetry: () => retried = true,
      ));

      expect(find.text("Couldn't load favorites"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('does not render technical details', (tester) async {
      await tester.pumpWidget(rowOf(
        'Something went wrong',
        onRetry: () {},
      ));

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });
  });
}
