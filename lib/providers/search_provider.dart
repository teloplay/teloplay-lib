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

/// [SearchHistoryRepository]-এর জন্য provider — অন্য providers থেকে
/// সহজে watch/read করা যাবে।
final searchHistoryRepositoryProvider = Provider<SearchHistoryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SearchHistoryRepository(db);
});

/// সাম্প্রতিক searches — search bar focus/empty অবস্থায় chip আকারে
/// দেখানোর জন্য। FutureProvider.autoDispose ব্যবহার করা হয়েছে কারণ এই
/// data সবসময় fresh থাকা দরকার (নতুন search হলে UI নিজে থেকেই
/// invalidate করে রিফ্রেশ করবে — নিচে [SearchController.search] দেখুন),
/// কিন্তু screen বন্ধ হলে dispose হয়ে যাওয়াই ঠিক (stale cache carry
/// করার দরকার নেই)।
final recentSearchesProvider =
    FutureProvider.autoDispose<List<RecentSearch>>((ref) async {
  final repo = ref.watch(searchHistoryRepositoryProvider);
  return repo.getRecentSearches();
});

/// একটা single multi-category search call-এর ফলাফল ধরে রাখার জন্য state
/// shape।
///
/// ⚠️ Phase 6.5B — Global Search Architecture। আগে এই ক্লাস শুধু
/// `results: List<SearchResult>` (songs-only) রাখত। এখন চারটা আলাদা
/// entity-type list রাখে — [songs] সবসময়ই populate হবে (engine-backed,
/// আগের মতোই), কিন্তু [albums]/[artists]/[playlists] খালিও থাকতে পারে
/// (কোনো matching data না থাকলে) — এটা bug না, বরং expected অবস্থা যতক্ষণ
/// না Songs টেবিলে albumId/artistId metadata বেশি populate হয় (দেখো
/// LibraryRepository.searchAlbums()/searchArtists() doc-comment)।
///
/// UI-এর নিয়ম (locked, developer অনুরোধে): কোনো section-এর list খালি
/// হলে UI সেই section সম্পূর্ণ hide করবে — কখনো "No albums found"-এর
/// মতো fake/empty placeholder section দেখাবে না। শুধু Songs section-এর
/// (top-level fallback) খালি অবস্থায় "No results" দেখানো যৌক্তিক, কারণ
/// পুরো search-ই তখন কিছু পায়নি।
class SearchState {
  final String query;
  final List<SearchResult> songs;
  final List<AlbumSearchResult> albums;
  final List<ArtistSearchResult> artists;
  final List<PlaylistSearchResult> playlists;
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

  /// কোনো category-তেই কিছু নেই কিনা — UI-র "No results" state-এর জন্য।
  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  /// "Top Result" হিসেবে দেখানোর জন্য সবচেয়ে প্রাসঙ্গিক single item —
  /// simple, deterministic priority: song > album > artist > playlist।
  /// এটা কোনো relevance-scoring algorithm না (সেটা Phase 7+ scope),
  /// শুধু "প্রথম যা পাওয়া গেছে সবচেয়ে নির্দিষ্ট category থেকে" — একটা
  /// exact-song-match সাধারণত সবচেয়ে বেশি user-intent বহন করে, তারপর
  /// album/artist/playlist ক্রমান্বয়ে বেশি broad।
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
    List<SearchResult>? songs,
    List<AlbumSearchResult>? albums,
    List<ArtistSearchResult>? artists,
    List<PlaylistSearchResult>? playlists,
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
      // error ইচ্ছাকৃতভাবে explicit `error` param দিয়েই সেট হয় —
      // পুরনো error carry না করে প্রতিটা নতুন search শুরুতে null থেকেই
      // শুরু হয় (নিচে `search()`-এ দেখুন)।
      error: error,
    );
  }
}

/// Cached per-query multi-entity bundle — SearchController-এর in-memory
/// cache এখন চারটা list-ই একসাথে ধরে রাখে (আগে শুধু songs list ছিল)।
class _CachedSearch {
  final List<SearchResult> songs;
  final List<AlbumSearchResult> albums;
  final List<ArtistSearchResult> artists;
  final List<PlaylistSearchResult> playlists;

  const _CachedSearch({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
  });
}

/// Debounced live multi-entity search + in-memory result cache-এর মূল
/// controller।
///
/// ⚠️ Riverpod v3 — এই project `flutter_riverpod: ^3.3.1` ব্যবহার করছে,
/// `Notifier`/`NotifierProvider` API (StateNotifier না)।
///
/// ⚠️ Phase 6.5B (Global Search Architecture) — আগে এই controller শুধু
/// `MusicPlayerRepository.search()` কল করত (songs-only)। এখন চারটা
/// independent query একসাথে (parallel, `Future.wait`) চালায়:
///   - Songs      → MusicPlayerRepository.search() (engine-backed, আগের মতোই)
///   - Albums     → LibraryRepository.searchAlbums()
///   - Artists    → LibraryRepository.searchArtists()
///   - Playlists  → PlaylistRepository.searchPlaylists()
///
/// Search capture (BehaviourTrackingService.recordSearch()) এখনও শুধু
/// songs query-এর ভেতর দিয়েই হয় (MusicPlayerRepository.search()-এর
/// existing behavior, duplicate করা হয়নি) — "recent searches" মানে এখনো
/// "যে query দিয়ে গান খোঁজা হয়েছে", multi-category হওয়ার পরেও এই
/// concept বদলায়নি।
///
/// In-memory cache: same query আবার এলে চারটা category-ই cache থেকে
/// আসে, কোনো repository আবার কল হয় না।
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

  /// প্রতি keystroke-এ কল হবে — debounce করে তারপর আসল search চালাবে।
  void onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    _debounce = Timer(_debounceDuration, () => search(query));
  }

  /// অবিলম্বে search চালানো (debounce ছাড়া) — Enter/chip/suggestion tap।
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

      // চারটা category একসাথে, parallel-এ — কোনোটা অন্যটার জন্য অপেক্ষা
      // করে না। একটা ব্যর্থ হলে (যেমন engine timeout) বাকিগুলো তবু
      // ফলাফল দিতে পারবে — তাই Future.wait-এর বদলে প্রতিটাকে আলাদা
      // try/catch-এ wrap করা হচ্ছে নিচে, একটার ব্যর্থতা পুরো search-কে
      // error state-এ পাঠাবে না।
      final results = await Future.wait([
        musicRepo.search(query).catchError((_) => <SearchResult>[]),
        libraryRepo.searchAlbums(query).catchError((_) => <AlbumSearchResult>[]),
        libraryRepo.searchArtists(query).catchError((_) => <ArtistSearchResult>[]),
        playlistRepo.searchPlaylists(query).catchError((_) => <PlaylistSearchResult>[]),
      ]);

      final songs = results[0] as List<SearchResult>;
      final albums = results[1] as List<AlbumSearchResult>;
      final artists = results[2] as List<ArtistSearchResult>;
      final playlists = results[3] as List<PlaylistSearchResult>;

      _cache[query] = _CachedSearch(
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
      );

      // দ্রুত পরপর টাইপ করলে stale ফলাফল দিয়ে newer state overwrite এড়ানো।
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
      // এই catch এখন শুধুই truly unexpected failure-এর জন্য (যেমন
      // provider read ব্যর্থতা) — প্রতিটা individual repository call
      // উপরে নিজের catchError() দিয়ে ইতিমধ্যে সুরক্ষিত।
      if (state.query != query) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Search bar clear করলে/screen ছাড়লে state আর pending debounce reset।
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
// Live Search Suggestions — song preview যোগ হয়েছে (Phase 6.5B)
// ─────────────────────────────────────────────────────────────────────────
//
// ⚠️ SuggestionController এখন দুটো parallel fetch করে প্রতিটা query-এ:
//   - Text suggestions → PlaybackEngine.searchSuggestions() (আগের মতোই)
//   - Song previews    → MusicPlayerRepository.search(query, limit: 5)
//
// Song preview concept-গতভাবে "suggestion dropdown-এ কয়েকটা actual
// matching track দেখানো, যাতে full search submit না করেও সরাসরি play
// করা যায়" — SearchController-এর multi-entity scope-এর অংশ না (সেখানে
// albums/artists/playlists-ও আছে), শুধু suggestion UX enhancement।
//
// ⚠️ Minor over-capture: repo.search() প্রতিটা keystroke-এ (150ms
// debounce-এর পর) BehaviourTrackingService.recordSearch() ট্রিগার করবে
// — "recent searches"-এ আধা-টাইপ করা query জমা হবে। এটা accepted
// trade-off এখনকার মতো — পরে MusicPlayerRepository.search()-এ একটা
// optional flag দিয়ে fix করা যাবে, এই batch-এ নয়।

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

/// Cached bundle for one query — text suggestions + a few song previews,
/// fetched together so re-typing the same query doesn't re-hit either.
class _CachedSuggestions {
  final List<String> suggestions;
  final List<SearchResult> songPreviews;

  const _CachedSuggestions({
    required this.suggestions,
    required this.songPreviews,
  });
}

/// ⚠️ Suggestion dropdown — song preview (this batch). Below the 5 text
/// suggestions, the dropdown now also shows a short list of actual
/// matching songs (thumbnail + title), so the user can jump straight to
/// playback without submitting the full search first.
///
/// Two independent fetches per query, run in parallel:
///   - Text suggestions → PlaybackEngine.searchSuggestions() (unchanged)
///   - Song previews    → MusicPlayerRepository.search(query, limit: 5)
///     (same engine-backed song search SearchController uses, just a
///     small limit and no BehaviourTrackingService capture — a
///     suggestion-time preview isn't a submitted search, so it
///     shouldn't count as one; MusicPlayerRepository.search() DOES
///     capture internally though, since that's shared with real search.
///     This is an accepted minor over-capture, not worth threading a
///     "skip tracking" flag through the shared method for a preview
///     list — see note below.)
///
/// One fetch failing doesn't blank the other (same independent-failure
/// pattern as SearchController.search()'s Future.wait + catchError).
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
        repo.searchSuggestions(query).catchError((_) => <String>[]);
    final Future<List<SearchResult>> songPreviewsFuture = repo
        .search(query, limit: _songPreviewLimit)
        .catchError((e, st) {
          AppLogger.error('[suggestion] songPreview search FAILED', e, st);
          return <SearchResult>[];
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