import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/playback/playback_engine.dart';
import 'package:teloplay/providers/smart_queue_provider.dart';
import 'package:teloplay/services/personalization_engine.dart';

/// P1-N — [resolveQueueAttribution] truthfulness contract: an attribution
/// is returned ONLY when the track both entered the queue via SmartQueue
/// auto-fill AND has a recorded algorithm reason. Everything else -> null
/// (UI shows no caption, never an invented reason).
void main() {
  SearchResult track(String id) => SearchResult(
        videoId: id,
        title: 'Title $id',
        author: 'Author',
        thumbnail: '',
      );

  ScoredCandidate candidate(String id, [String? label]) => ScoredCandidate(
        track: track(id),
        score: 500,
        reason: RecommendationReason.favoriteArtist,
        contextLabel: label ?? 'Because you love Author',
      );

  group('resolveQueueAttribution', () {
    test('returns candidate when auto-queued AND recorded', () {
      final c = candidate('v1');
      final result = resolveQueueAttribution(
        attributions: {'v1': c},
        autoQueuedIds: {'v1'},
        videoId: 'v1',
      );
      expect(result, same(c));
    });

    test('null when track was added manually (not auto-queued)', () {
      final result = resolveQueueAttribution(
        attributions: {'v1': candidate('v1')},
        autoQueuedIds: const {},
        videoId: 'v1',
      );
      expect(result, isNull);
    });

    test('null when auto-queued but reason record missing', () {
      final result = resolveQueueAttribution(
        attributions: const {},
        autoQueuedIds: {'v1'},
        videoId: 'v1',
      );
      expect(result, isNull);
    });

    test('null for unknown video id', () {
      final result = resolveQueueAttribution(
        attributions: {'v1': candidate('v1')},
        autoQueuedIds: {'v1'},
        videoId: 'other',
      );
      expect(result, isNull);
    });

    test('null when both inputs empty', () {
      final result = resolveQueueAttribution(
        attributions: const {},
        autoQueuedIds: const {},
        videoId: 'v1',
      );
      expect(result, isNull);
    });

    test('deterministic across calls', () {
      final c = candidate('v9');
      ScoredCandidate? run() => resolveQueueAttribution(
            attributions: {'v9': c},
            autoQueuedIds: {'v9'},
            videoId: 'v9',
          );
      expect(run(), same(run()));
    });
  });
}
