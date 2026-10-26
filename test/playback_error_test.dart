import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/playback/playback_engine.dart';
import 'package:teloplay/models/now_playing_model.dart';

/// P0-G4: pure mapper table. No seams, no I/O — every kind reachable.
void main() {
  group('playbackErrorFor', () {
    test('socket/timeout failures map to network + retryable', () {
      final err = playbackErrorFor(
        PlaybackEngineException('SocketException: connection timed out'),
      );
      expect(err.kind, PlaybackErrorKind.network);
      expect(err.retryable, isTrue);
      expect(err.message, isNotEmpty);
    });

    test('empty/no-result failures map to unavailable + not retryable', () {
      final err = playbackErrorFor(
        PlaybackEngineException('NO_STREAM for videoId=x'),
      );
      expect(err.kind, PlaybackErrorKind.unavailable);
      expect(err.retryable, isFalse);
    });

    test('other engine failures map to playback + retryable', () {
      final err = playbackErrorFor(
        PlaybackEngineException('cipher exploded'),
      );
      expect(err.kind, PlaybackErrorKind.playback);
      expect(err.retryable, isTrue);
    });

    test('non-engine failures map to unknown + retryable', () {
      final err = playbackErrorFor(StateError('weird'));
      expect(err.kind, PlaybackErrorKind.unknown);
      expect(err.retryable, isTrue);
    });

    test('cause is preserved for logging, never shown', () {
      final cause = Exception('raw-technical-detail');
      final err = playbackErrorFor(cause);
      expect(err.cause, same(cause));
      expect(err.message, isNot(contains('raw-technical-detail')));
    });

    // Batch 5 — remaining keyword table entries (one case per branch
    // keyword not covered above) + precedence: network wins over the
    // engine-type check below it.
    test('network/connection keywords map to network', () {
      for (final text in [
        'Network unreachable (host down)',
        'Connection reset by peer',
        'Request timed out after 30s',
        'operation timeout exceeded',
      ]) {
        final err = playbackErrorFor(PlaybackEngineException(text));
        expect(err.kind, PlaybackErrorKind.network, reason: text);
        expect(err.retryable, isTrue, reason: text);
      }
    });

    test('unavailable keywords map to unavailable + not retryable', () {
      for (final text in [
        'no result for query',
        'Track not found on backend',
        'content unavailable in region',
        'empty response body',
      ]) {
        final err = playbackErrorFor(PlaybackEngineException(text));
        expect(err.kind, PlaybackErrorKind.unavailable, reason: text);
        expect(err.retryable, isFalse, reason: text);
      }
    });
  });
}
