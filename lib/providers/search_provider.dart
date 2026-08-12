import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/playback/playback_engine.dart';
import '../data/repositories/search_history_repository.dart';
import '../models/search_models.dart';
import 'database_provider.dart';
import 'library_provider.dart';
import 'music_player_provider.dart';
import 'playlist_provider.dart';

// ─────────────────────────────────────────────────────────────────────────
// Search Orchestrator (NEW — your addition for preview + paginated search)
// ─────────────────────────────────────────────────────────────────────────

/// Search orchestrator with preview + paginated category search.
/// Wired into the existing SearchController for preview functionality.
class SearchOrchestrator {
  final dynamic innertube;
  final dynamic deezer;
  final dynamic cache;

  const SearchOrchestrator({
    required this.innertube,
    required this.deezer,
    required this.cache,
  });

  /// Live preview for mobile overlay — 3-4 items per category.
  Future<SearchPreview> searchPreview(String query) async {
    // TODO: Implement actual preview logic using innertube/deezer/cache
    // This is a stub — wire to actual services as needed.
    return SearchPreview(
      songs: [],
      albums: [],
      artists: [],
      playlists: [],
    );
  }

  /// Paginated category search for dedicated screens.
  Future<List<EnrichedSearchResult>> searchCategory(
    String query,
    SearchCategory category, {
    int page = 0,
  }) async {
    // TODO: Implement actual paginated category search
    // This is a stub — wire to actual services as needed.
    return [];
  }
}

/// Preview result bundle for mobile overlay.
class SearchPreview {
  final List<dynamic> songs;
  final List<dynamic> albums;
  final List<dynamic> artists;
  final List<dynamic> playlists;

  const SearchPreview({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });
}

/// Category enum for paginated search.
enum SearchCategory { songs, albums, artists, playlists }

/// Enriched search result with metadata.
class EnrichedSearchResult {
  final String id;
  final String title;
  final String? subtitle;
  final String? thumbnail;
  final SearchCategory category;

  const EnrichedSearchResult({
    required this.id,
    required this.title,
    this.subtitle,
    this.thumbnail,
    required this.category,
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Service Providers (NEW — wired for SearchOrchestrator)
// ─────────────────────────────────────────────────────────────────────────

final innertubeServiceProvider = Provider<dynamic>((ref) {
  // TODO: Wire to actual Innertube service
  throw UnimplementedError('innertubeServiceProvider not wired');
});

final deezerClientProvider = Provider<dynamic>((ref) {
  // TODO: Wire to actual Deezer client
  throw UnimplementedError('deezerClientProvider not wired');
});

final metadataCacheServiceProvider = Provider<dynamic>((ref) {
  // TODO: Wire to actual metadata cache service
  throw UnimplementedError('metadataCacheServiceProvider not wired');
});

final searchOrchestratorProvider = Provider<SearchOrchestrator>((ref) {
  return SearchOrchestrator(
    innertube: ref.watch(innertubeServiceProvider),
    deezer: ref.watch(deezerClientProvider),
    cache: ref.watch(metadataCacheServiceProvider),
  );
});

// ─────────────────────────────────────────────────────────────────────────
// Search History (EXISTING — unchanged)
// ─────────────────────────────────────────────────────────────────────────

final searchHistoryRepositoryProvider = Provider((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SearchHistoryRepository(db);
});

final recentSearchesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final repo = ref.watch(searchHistoryRepositoryProvider);
  final recents = await repo.getRecentSearches();  // List<RecentSearch>
  return recents.map((r) => r.query).toList();     // Extract String queries
});

// ─────────────────────────────────────────────────────────────────────────
// Search State (EXISTING — unchanged multi-entity shape)
// ─────────────────────────────────────────────────────────────────────────

class SearchState {
  final String query;
  final List<dynamic> songs;
  final List<dynamic> albums;
  final List<dynamic> artists;
  final List<dynamic> playlists;
  final bool isLoading;
  final String? error;

  const SearchState({
    this.query = '',
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
    List<dynamic>? songs,
    List<dynamic>? albums,
    List<dynamic>? artists,
    List<dynamic>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return SearchState(
      query: query ?? this.query,
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
  final List<dynamic> songs;
  final List<dynamic> albums;
  final List<dynamic> artists;
  final List<dynamic> playlists;

  const _CachedSearch({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
  });
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

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      state = const SearchState();
      return;
    }

    _debounce?.cancel();

    final cached = _cache[query];
    if (cached != null) {
      state = SearchState(
        query: query,
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
      final libraryRepo = ref.read(libraryRepositoryProvider);
      final playlistRepo = ref.read(playlistRepositoryProvider);

      final results = await Future.wait([
        musicRepo.search(query).catchError((_) => []),
        libraryRepo.searchAlbums(query).catchError((_) => []),
        libraryRepo.searchArtists(query).catchError((_) => []),
        playlistRepo.searchPlaylists(query).catchError((_) => []),
      ]);

      final songs = results[0] as List<dynamic>;
      final albums = results[1] as List<dynamic>;
      final artists = results[2] as List<dynamic>;
      final playlists = results[3] as List<dynamic>;

      _cache[query] = _CachedSearch(
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
      );

      if (state.query != query) return;

      state = state.copyWith(
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
        isLoading: false,
      );

      ref.invalidate(recentSearchesProvider);
    } catch (e) {
      if (state.query != query) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── NEW: Preview search (from your modified version) ──
  /// Live preview for mobile overlay — 3-4 items per category.
  /// Uses SearchOrchestrator for lightweight preview results.
  Future<SearchPreview> searchPreview(String query) async {
    if (query.trim().isEmpty) {
      return const SearchPreview();
    }

    final orchestrator = ref.read(searchOrchestratorProvider);
    return await orchestrator.searchPreview(query);
  }

  // ── NEW: Paginated category search (from your modified version) ──
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
  final List<dynamic> suggestions;
  final List<dynamic> songPreviews;
  final bool isLoading;

  const SuggestionState({
    this.query = '',
    this.suggestions = const [],
    this.songPreviews = const [],
    this.isLoading = false,
  });

  SuggestionState copyWith({
    String? query,
    List<dynamic>? suggestions,
    List<dynamic>? songPreviews,
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
  final List<dynamic> suggestions;
  final List<dynamic> songPreviews;

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

  void onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
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
      final Future<List<String>> suggestionsFuture =
          repo.searchSuggestions(query).catchError((_) => []);
      final Future<List<dynamic>> songPreviewsFuture = repo
          .search(query, limit: _songPreviewLimit)
          .catchError((e, st) {
        AppLogger.error('[suggestion] songPreview search FAILED', e, st);
        return [];
      });

      final suggestions = await suggestionsFuture;
      final songPreviews = await songPreviewsFuture;

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