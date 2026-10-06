import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../core/logging/app_logger.dart';
import '../core/playback/playback_engine.dart';
import '../data/repositories/music_player_repository.dart' show MusicPlayerRepository;
import '../data/repositories/search_history_repository.dart';
import '../models/search_models.dart';
import '../services/cache/metadata_cache_service.dart';
import '../services/metadata/deezer_client.dart';
import '../services/search/stream_matcher.dart';
import 'database_provider.dart';
import 'repository_providers.dart' show libraryRepositoryProvider;
import 'music_player_provider.dart';
import 'playlist_provider.dart';

// ─────────────────────────────────────────────────────────────────────────
// Search Orchestrator — v11 Metadata Architecture (real implementation)
// ─────────────────────────────────────────────────────────────────────────

class EnrichedSearchResult {
  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final String thumbnail;
  final Duration? duration;
  final bool isEnriched;

  const EnrichedSearchResult({
    required this.videoId,
    required this.title,
    required this.artist,
    this.album,
    required this.thumbnail,
    this.duration,
    required this.isEnriched,
  });

  factory EnrichedSearchResult.fromYoutubeOnly(SearchResult yt) =>
      EnrichedSearchResult(
        videoId: yt.videoId,
        title: yt.title,
        artist: yt.author,
        thumbnail: yt.thumbnail,
        duration: yt.duration,
        isEnriched: false,
      );

  factory EnrichedSearchResult.fromMatch(SearchResult yt, DeezerTrack dz) =>
      EnrichedSearchResult(
        videoId: yt.videoId,
        title: dz.title,
        artist: dz.artistName,
        album: dz.albumName,
        thumbnail: dz.albumCover ?? yt.thumbnail,
        duration: dz.duration ?? yt.duration,
        isEnriched: true,
      );
}

class SearchPreview {
  final List<EnrichedSearchResult> songs;
  final List<AlbumSearchResult> albums;
  final List<ArtistSearchResult> artists;
  final List<PlaylistSearchResult> playlists;

  const SearchPreview({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });
}

enum SearchCategory { songs, albums, artists, playlists }

class SearchOrchestrator {
  final Ref _ref;
  final DeezerClient _deezer;

  SearchOrchestrator(this._ref, this._deezer);

  Future<SearchPreview> searchPreview(String query) async {
    if (query.trim().isEmpty) return const SearchPreview();

    final musicRepo = _ref.read(musicPlayerRepositoryProvider);
    final libraryRepo = _ref.read(libraryRepositoryProvider);
    final playlistRepo = _ref.read(playlistRepositoryProvider);

    final results = await Future.wait([
      _enrichedSongs(query, limit: 4, musicRepo: musicRepo),
      libraryRepo.searchAlbums(query).catchError((_) => <AlbumSearchResult>[]),
      libraryRepo.searchArtists(query).catchError((_) => <ArtistSearchResult>[]),
      playlistRepo.searchPlaylists(query).catchError((_) => <PlaylistSearchResult>[]),
    ]);

    return SearchPreview(
      songs: (results[0] as List<EnrichedSearchResult>).take(4).toList(),
      albums: (results[1] as List<AlbumSearchResult>).take(4).toList(),
      artists: (results[2] as List<ArtistSearchResult>).take(4).toList(),
      playlists: (results[3] as List<PlaylistSearchResult>).take(4).toList(),
    );
  }

  Future<List<EnrichedSearchResult>> searchCategory(
    String query,
    SearchCategory category, {
    int page = 0,
    int pageSize = 20,
  }) async {
    if (category != SearchCategory.songs) {
      return const [];
    }

    final musicRepo = _ref.read(musicPlayerRepositoryProvider);
    final all = await _enrichedSongs(
      query,
      limit: pageSize * (page + 1),
      musicRepo: musicRepo,
    );
    return all.skip(page * pageSize).take(pageSize).toList();
  }

  /// Batch C — local-library category See-All (albums/artists/playlists).
  ///
  /// The existing repo methods return the FULL filtered local set (no
  /// pagination params — local DB sets are small), so the category
  /// screen slices in memory with the same page/pageSize contract as
  /// songs. No YouTube/catalog API is involved: these three categories
  /// are own-library data by architecture (same fan-out as
  /// [searchPreview]). Per-source failures yield `[]` (caller shows the
  /// named empty state, never raw errors).
  Future<List<AlbumSearchResult>> searchCategoryAlbums(
    String query, {
    int page = 0,
    int pageSize = 20,
  }) async {
    if (query.trim().isEmpty) return const [];
    final libraryRepo = _ref.read(libraryRepositoryProvider);
    final all = await libraryRepo
        .searchAlbums(query)
        .catchError((_) => <AlbumSearchResult>[]);
    return all.skip(page * pageSize).take(pageSize).toList();
  }

  /// Batch C — see [searchCategoryAlbums]; artist variant.
  Future<List<ArtistSearchResult>> searchCategoryArtists(
    String query, {
    int page = 0,
    int pageSize = 20,
  }) async {
    if (query.trim().isEmpty) return const [];
    final libraryRepo = _ref.read(libraryRepositoryProvider);
    final all = await libraryRepo
        .searchArtists(query)
        .catchError((_) => <ArtistSearchResult>[]);
    return all.skip(page * pageSize).take(pageSize).toList();
  }

  /// Batch C — see [searchCategoryAlbums]; own-playlists variant.
  /// Empty for signed-out users (playlist query is user-scoped) — the
  /// caller renders the named empty state, never a login wall here.
  Future<List<PlaylistSearchResult>> searchCategoryPlaylists(
    String query, {
    int page = 0,
    int pageSize = 20,
  }) async {
    if (query.trim().isEmpty) return const [];
    final playlistRepo = _ref.read(playlistRepositoryProvider);
    final all = await playlistRepo
        .searchPlaylists(query)
        .catchError((_) => <PlaylistSearchResult>[]);
    return all.skip(page * pageSize).take(pageSize).toList();
  }

  Future<List<EnrichedSearchResult>> _enrichedSongs(
    String query, {
    required int limit,
    required MusicPlayerRepository musicRepo,
  }) async {
    AppLogger.search('Orchestrator search: $query');

    final List<SearchResult> ytResults =
        await musicRepo.search(query, limit: limit).catchError((_) => <SearchResult>[]);

    List<DeezerTrack> dzResults = const [];
    try {
      dzResults = await _deezer
          .searchTracks(query, limit: limit)
          .timeout(const Duration(milliseconds: 400), onTimeout: () => const []);
    } catch (e) {
      AppLogger.search('Deezer enrichment skipped: $e');
    }

    if (dzResults.isEmpty) {
      return ytResults.map(EnrichedSearchResult.fromYoutubeOnly).toList();
    }

    return ytResults.map((yt) {
      final match = StreamMatcher.findBestMatch(
        deezerTracks: dzResults,
        youtubeResult: yt,
      );
      return match != null
          ? EnrichedSearchResult.fromMatch(yt, match)
          : EnrichedSearchResult.fromYoutubeOnly(yt);
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Service Providers
// ─────────────────────────────────────────────────────────────────────────

final metadataCacheServiceProvider = Provider((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MetadataCacheService(db: db);
});

final deezerClientProvider = Provider((ref) {
  return DeezerClient(
    appId: EnvConfig.deezerAppId.isEmpty ? null : EnvConfig.deezerAppId,
    secret: EnvConfig.deezerSecret,
    cache: ref.watch(metadataCacheServiceProvider),
  );
});

final searchOrchestratorProvider = Provider((ref) {
  return SearchOrchestrator(ref, ref.watch(deezerClientProvider));
});

// ─────────────────────────────────────────────────────────────────────────
// Search History (EXISTING — unchanged)
// ─────────────────────────────────────────────────────────────────────────

final searchHistoryRepositoryProvider = Provider((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SearchHistoryRepository(db);
});

// FIX: getRecentSearches() returns List<RecentSearch>, not List<String>
// RecentSearch has a .query field (String). We map to extract queries.
final recentSearchesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final repo = ref.watch(searchHistoryRepositoryProvider);
  final recentSearches = await repo.getRecentSearches();
  return recentSearches.map((r) => r.query).toList();
});

// ─────────────────────────────────────────────────────────────────────────
// Search State (EXISTING — unchanged multi-entity shape)
// ─────────────────────────────────────────────────────────────────────────

class SearchState {
  final String query;

  /// P1-K — typo correction: when the displayed results come from a
  /// server-suggested correction, this holds the ORIGINAL typed query
  /// (null = results are for [query] itself). UI shows a one-line banner;
  /// never auto-loops (correction runs at most once per submit).
  final String? correctedFrom;
  final List<SearchResult> songs;
  final List<AlbumSearchResult> albums;
  final List<ArtistSearchResult> artists;
  final List<PlaylistSearchResult> playlists;
  final bool isLoading;
  final String? error;

  const SearchState({
    this.query = '',
    this.correctedFrom,
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  ({SearchEntityType type, Object item})? get topResult {
    if (songs.isNotEmpty) {
      return (type: SearchEntityType.song, item: songs.first);
    }
    if (albums.isNotEmpty) {
      return (type: SearchEntityType.album, item: albums.first);
    }
    if (artists.isNotEmpty) {
      return (type: SearchEntityType.artist, item: artists.first);
    }
    if (playlists.isNotEmpty) {
      return (type: SearchEntityType.playlist, item: playlists.first);
    }
    return null;
  }

  SearchState copyWith({
    String? query,
    String? correctedFrom,
    List<SearchResult>? songs,
    List<AlbumSearchResult>? albums,
    List<ArtistSearchResult>? artists,
    List<PlaylistSearchResult>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return SearchState(
      query: query ?? this.query,
      correctedFrom: correctedFrom,
      songs: songs ?? this.songs,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class _CachedSearch {
  final List<SearchResult> songs;
  final List<AlbumSearchResult> albums;
  final List<ArtistSearchResult> artists;
  final List<PlaylistSearchResult> playlists;
  final String? correctedFrom;

  const _CachedSearch({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
    this.correctedFrom,
  });
}

/// P1-K — bounded typo tolerance, pure (unit-tested, no seams).
/// Returns the first server suggestion that differs from the typed query
/// (case-insensitive), else null. The caller runs at most ONE follow-up
/// search with it, only when the exact query returned zero results —
/// no extra latency when suggestions are absent, no loops by construction.
String? correctionCandidate(String query, List<String> suggestions) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return null;
  for (final s in suggestions) {
    final t = s.trim();
    if (t.isEmpty) continue;
    if (t.toLowerCase() != q) return t;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────
// Search Controller (EXISTING — merged with your preview method)
// ─────────────────────────────────────────────────────────────────────────

class SearchController extends Notifier<SearchState> {
  Timer? _debounce;
  final Map<String, _CachedSearch> _cache = {};
  static const _debounceDuration = Duration(milliseconds: 400);

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
    });
    return const SearchState();
  }

  void onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    _debounce = Timer(_debounceDuration, () => search(query));
  }

  Future<void> search(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      state = const SearchState();
      return Future.value();
    }
    return _searchInternal(query, isCorrection: false, originalQuery: null);
  }

  Future<void> _searchInternal(
    String query, {
    required bool isCorrection,
    required String? originalQuery,
  }) async {
    _debounce?.cancel();

    final cached = _cache[query];
    if (cached != null) {
      state = SearchState(
        query: query,
        correctedFrom: cached.correctedFrom,
        songs: cached.songs,
        albums: cached.albums,
        artists: cached.artists,
        playlists: cached.playlists,
      );
      return;
    }

    state = state.copyWith(query: query, isLoading: true, error: null);

    try {
      final musicRepo = ref.read(musicPlayerRepositoryProvider);

      // ⚠️ OpenTune-parity: use rich multi-entity searchSections instead of
      // song-only search(). Searches YouTube across all types (songs/albums/
      // artists/playlists/videos) in one call, matching OpenTune's behavior.
      // limitPerSection=0 means NO LIMIT (show all results like OpenTune).
      final sections = await musicRepo.searchSections(query, limitPerSection: 0);

      final songs = <SearchResult>[];
      final albums = <AlbumSearchResult>[];
      final artists = <ArtistSearchResult>[];
      final playlists = <PlaylistSearchResult>[];

      // Parse sections into typed lists
      for (final section in sections) {
        for (final item in section.items) {
          switch (item.type) {
            case 'song':
              songs.add(SearchResult(
                videoId: item.id,
                title: item.title,
                author: item.subtitle ?? 'Unknown',
                thumbnail: item.thumbnail,
                duration: item.duration,
              ));
            case 'album':
              albums.add(AlbumSearchResult(
                albumId: item.id,
                albumName: item.title,
                artworkUrl: item.thumbnail,
                artistName: item.subtitle,
              ));
            case 'artist':
              artists.add(ArtistSearchResult(
                artistId: item.id,
                artistName: item.title,
                artworkUrl: item.thumbnail,
              ));
            case 'playlist':
              playlists.add(PlaylistSearchResult(
                playlistId: item.id,
                name: item.title,
                itemCount: int.tryParse(item.subtitle?.split(' ').first ?? '0') ?? 0,
                coverThumbnail: item.thumbnail,
              ));
          }
        }
      }

      final isEmptyResult =
          songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

      // P1-K — single bounded correction: exact query empty + a distinct
      // server suggestion exists → one follow-up search, then stop
      // (isCorrection guard forbids recursion).
      if (isEmptyResult && !isCorrection) {
        final candidate = correctionCandidate(
          query,
          ref.read(suggestionControllerProvider).suggestions,
        );
        if (candidate != null) {
          await _searchInternal(
            candidate,
            isCorrection: true,
            originalQuery: query,
          );
          return;
        }
      }

      _cache[query] = _CachedSearch(
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
        correctedFrom: isCorrection ? originalQuery : null,
      );

      if (state.query != query) return;

      state = state.copyWith(
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
        correctedFrom: isCorrection ? originalQuery : null,
        isLoading: false,
      );

      ref.invalidate(recentSearchesProvider);
    } catch (e) {
      if (state.query != query) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Live preview for mobile overlay — 3-4 items per category.
  Future<SearchPreview> searchPreview(String query) async {
    if (query.trim().isEmpty) {
      return const SearchPreview();
    }

    final orchestrator = ref.read(searchOrchestratorProvider);
    return await orchestrator.searchPreview(query);
  }

  /// Paginated category search for dedicated screens.
  Future<List<EnrichedSearchResult>> searchCategory(
    String query,
    SearchCategory category, {
    int page = 0,
  }) async {
    final orchestrator = ref.read(searchOrchestratorProvider);
    return await orchestrator.searchCategory(query, category, page: page);
  }

  void clear() {
    _debounce?.cancel();
    state = const SearchState();
  }
}

final searchControllerProvider =
    NotifierProvider.autoDispose<SearchController, SearchState>(
  SearchController.new,
);

// ─────────────────────────────────────────────────────────────────────────
// Suggestion State & Controller (EXISTING — unchanged)
// ─────────────────────────────────────────────────────────────────────────

class SuggestionState {
  final String query;
  final List<String> suggestions;
  final List<SearchResult> songPreviews;
  final bool isLoading;

  const SuggestionState({
    this.query = '',
    this.suggestions = const [],
    this.songPreviews = const [],
    this.isLoading = false,
  });

  SuggestionState copyWith({
    String? query,
    List<String>? suggestions,
    List<SearchResult>? songPreviews,
    bool? isLoading,
  }) {
    return SuggestionState(
      query: query ?? this.query,
      suggestions: suggestions ?? this.suggestions,
      songPreviews: songPreviews ?? this.songPreviews,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class _CachedSuggestions {
  final List<String> suggestions;
  final List<SearchResult> songPreviews;

  const _CachedSuggestions({
    required this.suggestions,
    required this.songPreviews,
  });
}

class SuggestionController extends Notifier<SuggestionState> {
  Timer? _debounce;
  final Map<String, _CachedSuggestions> _cache = {};
  static const _debounceDuration = Duration(milliseconds: 150);
  static const _songPreviewLimit = 5;

  @override
  SuggestionState build() {
    ref.onDispose(() {
      _debounce?.cancel();
    });
    return const SuggestionState();
  }

  void onQueryChanged(String rawQuery) {
    _debounce?.cancel();

    // ⚠️ Trailing/leading-space fix — earlier this used the raw
    // (untrimmed) text as both the cache key and the value sent to the
    // suggest API. Typing "kei" then a space produced "kei " which is a
    // *different* cache key, so it always missed cache, went to
    // _fetch(), and hit YouTube's suggest endpoint with a trailing
    // space — which YouTube typically answers with an empty/near-empty
    // result. The dropdown then looked "frozen"/unresponsive right when
    // space was pressed. We now key everything off the trimmed query,
    // so trailing spaces reuse the already-fetched suggestions instead
    // of triggering a doomed network call.
    final query = rawQuery.trim();

    if (query.isEmpty) {
      state = const SuggestionState();
      return;
    }

    final cached = _cache[query];
    if (cached != null) {
      state = SuggestionState(
        query: query,
        suggestions: cached.suggestions,
        songPreviews: cached.songPreviews,
      );
      return;
    }

    state = state.copyWith(query: query, isLoading: true);
    _debounce = Timer(_debounceDuration, () => _fetch(query));
  }

  Future<void> _fetch(String query) async {
    AppLogger.playback('[suggestion] _fetch STARTED for query="$query"');
    final repo = ref.read(musicPlayerRepositoryProvider);

    try {
      // ⚠️ OpenTune-parity: use rich suggestions (queries + item previews)
      // in a single call instead of separate text + song search calls.
      // This matches OpenTune's SearchSuggestions(queries, recommendedItems).
      final richSuggestions = await repo.searchSuggestionsRich(query);

      final suggestions = richSuggestions.queries;
      final songPreviews = richSuggestions.items
          .where((item) => item.type == 'song')
          .take(_songPreviewLimit)
          .map((item) => SearchResult(
                videoId: item.id,
                title: item.title,
                author: item.subtitle ?? 'Unknown',
                thumbnail: item.thumbnail,
                duration: item.duration,
              ))
          .toList();

      AppLogger.playback(
        '[suggestion] _fetch RESULT query="$query" '
        'suggestions=${suggestions.length} songPreviews=${songPreviews.length}',
      );

      _cache[query] = _CachedSuggestions(
        suggestions: suggestions,
        songPreviews: songPreviews,
      );

      if (state.query != query) {
        AppLogger.playback('[suggestion] STALE, discarding "$query"');
        return;
      }

      state = state.copyWith(
        suggestions: suggestions,
        songPreviews: songPreviews,
        isLoading: false,
      );

      AppLogger.playback(
        '[suggestion] STATE UPDATED — songPreviews now = '
        '${state.songPreviews.length}',
      );
    } catch (e) {
      AppLogger.error('[suggestion] _fetch CRASHED', e);
      if (state.query != query) return;
      state = state.copyWith(isLoading: false);
    }
  }

  void clear() {
    _debounce?.cancel();
    state = const SuggestionState();
  }
}

final suggestionControllerProvider =
    NotifierProvider.autoDispose<SuggestionController, SuggestionState>(
  SuggestionController.new,
);