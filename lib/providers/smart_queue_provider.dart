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

class SmartQueueState {
  final bool isEnabled;
  final List<ScoredCandidate> upcomingRecommendations;
  final bool isLoading;

  const SmartQueueState({
    this.isEnabled = true,
    this.upcomingRecommendations = const [],
    this.isLoading = false,
  });

  SmartQueueState copyWith({
    bool? isEnabled,
    List<ScoredCandidate>? upcomingRecommendations,
    bool? isLoading,
  }) {
    return SmartQueueState(
      isEnabled: isEnabled ?? this.isEnabled,
      upcomingRecommendations: upcomingRecommendations ?? this.upcomingRecommendations,
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
      state = state.copyWith(
        upcomingRecommendations: candidates,
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
