import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_engine.dart';
import '../data/repositories/recommendation_repository.dart';
import '../data/repositories/library_repository.dart';
import '../services/personalization_engine.dart';
import 'database_provider.dart';
import 'repository_providers.dart';

final personalizationEngineProvider = Provider<PersonalizationEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final libraryRepo = ref.watch(libraryRepositoryProvider);
  return PersonalizationEngine(
    db: db,
    libraryRepo: libraryRepo,
  );
});

final recommendationRepositoryProvider = Provider<RecommendationRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final engine = ref.watch(personalizationEngineProvider);
  final libraryRepo = ref.watch(libraryRepositoryProvider);
  return RecommendationRepository(
    db,
    engine: engine,
    libraryRepo: libraryRepo,
  );
});

/// P1-N — pure attribution resolver (unit-tested, deterministic).
///
/// Returns the [ScoredCandidate] only when BOTH hold:
/// - [videoId] is currently flagged as SmartQueue-queued by the playback
///   repository ([MusicPlayerRepository.isAutoQueued]), i.e. the track
///   entered the queue via auto-fill rather than a manual add; and
/// - [videoId] has a recorded recommendation in [attributions], i.e. the
///   algorithm actually produced it with a reason.
///
/// Any other combination returns null and the UI shows no attribution —
/// never a fabricated reason.
ScoredCandidate? resolveQueueAttribution({
  required Map<String, ScoredCandidate> attributions,
  required Set<String> autoQueuedIds,
  required String videoId,
}) {
  if (!autoQueuedIds.contains(videoId)) return null;
  return attributions[videoId];
}

class SmartQueueState {
  final bool isEnabled;
  final List<ScoredCandidate> upcomingRecommendations;

  /// P1-N — accumulated reason records keyed by videoId across fetches
  /// (in-memory only, capped). Lets the queue surface the actual reason
  /// a SmartQueue-added track was recommended, after [upcomingRecommendations]
  /// has been replaced by a later fetch.
  final Map<String, ScoredCandidate> attributions;
  final bool isLoading;

  const SmartQueueState({
    this.isEnabled = true,
    this.upcomingRecommendations = const [],
    this.attributions = const {},
    this.isLoading = false,
  });

  SmartQueueState copyWith({
    bool? isEnabled,
    List<ScoredCandidate>? upcomingRecommendations,
    Map<String, ScoredCandidate>? attributions,
    bool? isLoading,
  }) {
    return SmartQueueState(
      isEnabled: isEnabled ?? this.isEnabled,
      upcomingRecommendations:
          upcomingRecommendations ?? this.upcomingRecommendations,
      attributions: attributions ?? this.attributions,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SmartQueueNotifier extends StateNotifier<SmartQueueState> {
  final RecommendationRepository _repo;

  SmartQueueNotifier(this._repo) : super(const SmartQueueState());

  void toggleEnabled() {
    state = state.copyWith(isEnabled: !state.isEnabled);
  }

  Future<List<SearchResult>> fetchAutoQueue({
    SearchResult? currentTrack,
    List<String> currentQueueIds = const [],
  }) async {
    if (!state.isEnabled) return [];

    state = state.copyWith(isLoading: true);
    try {
      final candidates = await _repo.getSmartQueue(
        seedTrack: currentTrack,
        excludeIds: currentQueueIds,
        count: 5,
      );
      // P1-N — accumulate reason records (insertion-ordered; newest
      // fetch wins per id; evict oldest beyond the cap). In-memory only.
      final merged = Map<String, ScoredCandidate>.of(state.attributions);
      for (final c in candidates) {
        merged.remove(c.track.videoId);
        merged[c.track.videoId] = c;
      }
      while (merged.length > 100) {
        merged.remove(merged.keys.first);
      }
      state = state.copyWith(
        upcomingRecommendations: candidates,
        attributions: Map.unmodifiable(merged),
        isLoading: false,
      );
      return candidates.map((c) => c.track).toList();
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return [];
    }
  }
}

final smartQueueProvider =
    StateNotifierProvider<SmartQueueNotifier, SmartQueueState>((ref) {
  final repo = ref.watch(recommendationRepositoryProvider);
  return SmartQueueNotifier(repo);
});
