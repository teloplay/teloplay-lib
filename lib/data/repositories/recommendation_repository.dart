import '../../core/playback/playback_engine.dart';
import '../../models/statistics_model.dart';
import '../../services/personalization_engine.dart';
import '../drift/database.dart';
import 'base_repository.dart';
import 'library_repository.dart';

/// Repository for personalized recommendations, mixes, radios, and statistics.
class RecommendationRepository extends BaseRepository {
  final PersonalizationEngine _engine;
  final LibraryRepository _libraryRepo;

  RecommendationRepository(
    AppDatabase db, {
    required PersonalizationEngine engine,
    required LibraryRepository libraryRepo,
  })  : _engine = engine,
        _libraryRepo = libraryRepo,
        super(db);

  /// Fetch Smart Auto-Queue recommendations.
  Future<List<ScoredCandidate>> getSmartQueue({
    SearchResult? seedTrack,
    List<String> excludeIds = const [],
    int count = 10,
  }) {
    return _engine.generateSmartQueue(
      seedTrack: seedTrack,
      excludeIds: excludeIds,
      count: count,
    );
  }

  /// Fetch user listening statistics and streaks.
  Future<UserListeningStats> getUserStats() {
    return _libraryRepo.getUserListeningStats();
  }

  /// P1-P — listening-maturity score inputs (existing signals only).
  /// Mirrors [getUserStats]: composition over [LibraryRepository], no new
  /// provider, no new storage.
  Future<ListeningMaturity> getListeningMaturity() {
    return _libraryRepo.getListeningMaturity();
  }

  /// Generate Artist Radio.
  Future<List<SearchResult>> getArtistRadio(String artistName, {int count = 20}) {
    return _engine.generateArtistRadio(artistName, count: count);
  }

  /// Generate Genre Radio.
  Future<List<SearchResult>> getGenreRadio(String genre, {int count = 20}) {
    return _engine.generateGenreRadio(genre, count: count);
  }

  /// Reorder search results by taste score.
  Future<List<SearchResult>> personalizeSearch(List<SearchResult> results) {
    return _engine.personalizeSearchResults(results);
  }
}
