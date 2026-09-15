import 'dart:async';
import 'dart:math';

import '../core/logging/app_logger.dart';
import '../core/playback/playback_engine.dart';
import '../data/drift/database.dart';
import '../data/repositories/library_repository.dart';
import 'cache/metadata_cache_service.dart';
import 'discovery/discovery_queue.dart';

enum RecommendationReason {
  frequentlyPlayed('Frequently Played'),
  favoriteArtist('Because you love this artist'),
  timeOfDayVibe('Matches your current vibe'),
  similarToRecent('Because you listened recently'),
  libraryDiscovery('From your library collection'),
  trendingDiscovery('Trending discovery'),
  smartAutoQueue('Smart Auto-Queue');

  final String label;
  const RecommendationReason(this.label);
}

class ScoredCandidate {
  final SearchResult track;
  final int score;
  final RecommendationReason reason;
  final String? contextLabel;

  const ScoredCandidate({
    required this.track,
    required this.score,
    required this.reason,
    this.contextLabel,
  });
}

class PersonalizationEngine {
  final AppDatabase _db;
  final LibraryRepository _libraryRepo;
  final MetadataCacheService? _metadataCache;
  final DiscoveryQueue? _discoveryQueue;

  PersonalizationEngine({
    required AppDatabase db,
    required LibraryRepository libraryRepo,
    MetadataCacheService? metadataCache,
    DiscoveryQueue? discoveryQueue,
  })  : _db = db,
        _libraryRepo = libraryRepo,
        _metadataCache = metadataCache,
        _discoveryQueue = discoveryQueue;

  Future<List<ScoredCandidate>> generateSmartQueue({
    SearchResult? seedTrack,
    List<String> excludeIds = const [],
    int count = 10,
  }) async {
    final pool = await _buildCandidatePool(excludeIds: excludeIds);
    if (pool.isEmpty) return [];

    final now = DateTime.now();
    final scored = <ScoredCandidate>[];

    final topArtists = (await _libraryRepo.getMostPlayed(limit: 5))
        .map((e) => e.author.toLowerCase())
        .toSet();

    for (final song in pool) {
      int score = 0;
      RecommendationReason reason = RecommendationReason.smartAutoQueue;
      String? contextLabel;

      if (seedTrack != null) {
        if (song.author.toLowerCase() == seedTrack.author.toLowerCase()) {
          score += 350;
          reason = RecommendationReason.favoriteArtist;
          contextLabel = 'More from ${seedTrack.author}';
        }
      }

      if (topArtists.contains(song.author.toLowerCase())) {
        score += 200;
        if (contextLabel == null) {
          reason = RecommendationReason.frequentlyPlayed;
          contextLabel = 'Because you love ${song.author}';
        }
      }

      score += song.cachedLocally ? 150 : 100;

      final hour = now.hour;
      if (hour >= 22 || hour < 5) {
        score += 40;
      } else if (hour >= 5 && hour < 12) {
        score += 40;
      }

      score += Random().nextInt(50);

      final trackResult = SearchResult(
        videoId: song.id,
        title: song.title,
        author: song.author,
        thumbnail: song.thumbnail,
        duration: song.durationSeconds != null ? Duration(seconds: song.durationSeconds!) : null,
      );

      scored.add(ScoredCandidate(
        track: trackResult,
        score: score,
        reason: reason,
        contextLabel: contextLabel ?? reason.label,
      ));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    final filtered = <ScoredCandidate>[];
    String? lastArtist;
    int artistCount = 0;

    for (final candidate in scored) {
      if (candidate.track.author == lastArtist) {
        if (artistCount < 2) {
          filtered.add(candidate);
          artistCount++;
        }
      } else {
        filtered.add(candidate);
        lastArtist = candidate.track.author;
        artistCount = 1;
      }
      if (filtered.length >= count) break;
    }

    return filtered;
  }

  Future<bool> predictSkip(String songId) async {
    final stats = await _libraryRepo.getBehaviourStats(songId: songId);
    return stats.skipRate >= 0.7 && stats.playCount >= 3;
  }

  Future<List<SearchResult>> personalizeSearchResults(List<SearchResult> rawResults) async {
    if (rawResults.isEmpty) return rawResults;

    final stats = await _libraryRepo.getUserListeningStats();
    final topArtistNames = stats.topArtists.map((a) => a.artistName.toLowerCase()).toSet();

    final scoredList = rawResults.map((track) {
      int tasteScore = 0;
      final authorLower = track.author.toLowerCase();
      if (topArtistNames.contains(authorLower)) tasteScore += 300;
      return (track: track, score: tasteScore);
    }).toList();

    scoredList.sort((a, b) => b.score.compareTo(a.score));
    return scoredList.map((e) => e.track).toList();
  }

  Future<List<SearchResult>> generateArtistRadio(String artistName, {int count = 20}) async {
    _discoveryQueue?.enqueueSimilarArtists(artistName);

    final allSongs = await (_db.select(_db.songs)
          ..where((t) => t.author.equals(artistName)))
        .get();

    final results = allSongs.map((s) => SearchResult(
          videoId: s.id,
          title: s.title,
          author: s.author,
          thumbnail: s.thumbnail,
          duration: s.durationSeconds != null ? Duration(seconds: s.durationSeconds!) : null,
        )).toList();

    return results.take(count).toList();
  }

  Future<List<SearchResult>> generateGenreRadio(String genre, {int count = 20}) async {
    final allSongs = await (_db.select(_db.songs)
          ..where((t) => t.genre.equals(genre)))
        .get();

    final results = allSongs.map((s) => SearchResult(
          videoId: s.id,
          title: s.title,
          author: s.author,
          thumbnail: s.thumbnail,
          duration: s.durationSeconds != null ? Duration(seconds: s.durationSeconds!) : null,
        )).toList();

    results.shuffle();
    return results.take(count).toList();
  }

  Future<List<Song>> _buildCandidatePool({List<String> excludeIds = const []}) async {
    final query = _db.select(_db.songs);
    if (excludeIds.isNotEmpty) {
      query.where((t) => t.id.isNotIn(excludeIds));
    }
    return query.get();
  }
}
