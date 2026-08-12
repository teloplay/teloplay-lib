import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../metadata/deezer_client.dart';
import '../metadata/metadata_cache_service.dart';
import '../playback/innertube_service.dart';
import 'stream_matcher.dart';

/// Unified search result enriched with metadata.
class EnrichedSearchResult {
  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final String thumbnail;
  final Duration? duration;
  final bool isEnriched; // true = Deezer match found, false = YouTube-only

  const EnrichedSearchResult({
    required this.videoId,
    required this.title,
    required this.artist,
    this.album,
    required this.thumbnail,
    this.duration,
    required this.isEnriched,
  });
}

/// Orchestrates parallel YouTube + Deezer search with non-blocking enrichment.
class SearchOrchestrator {
  final InnertubeService _innertube;
  final DeezerClient _deezer;
  final MetadataCacheService _cache;

  SearchOrchestrator({
    required InnertubeService innertube,
    required DeezerClient deezer,
    required MetadataCacheService cache,
  })  : _innertube = innertube,
        _deezer = deezer,
        _cache = cache;

  /// Search with instant YouTube results + background Deezer enrichment.
  /// Target: <300-400ms for initial results.
  Future<List<EnrichedSearchResult>> search(String query, {int limit = 20}) async {
    AppLogger.search('Orchestrator search: $query');

    // 1. Start YouTube search (always, no timeout — it's the backbone)
    final ytFuture = _innertube.search(query, limit: limit);

    // 2. Start Deezer search with 400ms timeout
    final dzFuture = _deezer.searchTracks(query, limit: limit)
        .timeout(const Duration(milliseconds: 400), onTimeout: () => []);

    // 3. Await both
    final ytResults = await ytFuture;
    List<DeezerTrack> dzResults;
    try {
      dzResults = await dzFuture;
    } catch (e) {
      AppLogger.search('Deezer timeout/error: $e');
      dzResults = [];
    }

    // 4. Merge: match Deezer tracks to YouTube results
    final enriched = <EnrichedSearchResult>[];
    for (final yt in ytResults) {
      final match = StreamMatcher.findBestMatch(
        deezerTracks: dzResults,
        youtubeResult: yt,
      );

      if (match != null) {
        enriched.add(EnrichedSearchResult(
          videoId: yt.videoId,
          title: match.title,           // Clean Deezer title
          artist: match.artistName,      // Clean Deezer artist
          album: match.albumName,
          thumbnail: match.albumCover ?? yt.thumbnail, // Deezer thumbnail preferred
          duration: match.duration,
          isEnriched: true,
        ));
      } else {
        enriched.add(EnrichedSearchResult(
          videoId: yt.videoId,
          title: yt.title,               // Raw YouTube title
          artist: yt.channelName,        // Channel as artist fallback
          thumbnail: yt.thumbnail,
          duration: yt.duration,
          isEnriched: false,
        ));
      }
    }

    // 5. Cache Deezer results for discovery layer
    for (final dz in dzResults) {
      await _cache.set(
        source: 'deezer',
        type: 'track',
        id: dz.id,
        data: dz.toJson(),
      );
    }

    AppLogger.search('Search complete: ${enriched.length} results '
        '(${enriched.where((e) => e.isEnriched).length} enriched)');

    return enriched;
  }

  /// Preview search: 3-4 items per category for mobile overlay.
  Future<SearchPreview> searchPreview(String query) async {
    final all = await search(query, limit: 16);
    return SearchPreview(
      songs: all.where((r) => r.isEnriched).take(4).toList(),
      albums: [], // Populated by separate album search if needed
      artists: [],
      playlists: [],
    );
  }

  /// Paginated category search for dedicated screens.
  Future<List<EnrichedSearchResult>> searchCategory(
    String query,
    SearchCategory category, {
    int page = 0,
    int pageSize = 20,
  }) async {
    // Category-specific search logic
    switch (category) {
      case SearchCategory.songs:
        return search(query, limit: pageSize * (page + 1))
            .then((r) => r.skip(page * pageSize).take(pageSize).toList());
      case SearchCategory.albums:
        final albums = await _deezer.searchAlbums(query, limit: pageSize, offset: page * pageSize);
        return albums.map((a) => EnrichedSearchResult(
          videoId: '', // Albums don't have videoId directly
          title: a.name,
          artist: a.artistName,
          thumbnail: a.cover,
          isEnriched: true,
        )).toList();
      case SearchCategory.artists:
        final artists = await _deezer.searchArtists(query, limit: pageSize, offset: page * pageSize);
        return artists.map((a) => EnrichedSearchResult(
          videoId: '',
          title: a.name,
          artist: a.name,
          thumbnail: a.picture,
          isEnriched: true,
        )).toList();
      case SearchCategory.playlists:
        // YouTube playlists only for now
        return search(query, limit: pageSize); // Simplified
    }
  }
}

/// Preview result for mobile search overlay.
class SearchPreview {
  final List<EnrichedSearchResult> songs;
  final List<EnrichedSearchResult> albums;
  final List<EnrichedSearchResult> artists;
  final List<EnrichedSearchResult> playlists;

  SearchPreview({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
  });
}

enum SearchCategory {
  songs('Songs'),
  albums('Albums'),
  artists('Artists'),
  playlists('Playlists');

  final String label;
  const SearchCategory(this.label);
}

// Placeholder models for Deezer responses
class DeezerTrack {
  final String id;
  final String title;
  final String artistName;
  final String? albumName;
  final String? albumCover;
  final Duration? duration;

  DeezerTrack({
    required this.id,
    required this.title,
    required this.artistName,
    this.albumName,
    this.albumCover,
    this.duration,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artistName': artistName,
    'albumName': albumName,
    'albumCover': albumCover,
    'duration': duration?.inSeconds,
  };
}

class DeezerAlbum {
  final String id;
  final String name;
  final String artistName;
  final String cover;

  DeezerAlbum({
    required this.id,
    required this.name,
    required this.artistName,
    required this.cover,
  });
}

class DeezerArtist {
  final String id;
  final String name;
  final String picture;

  DeezerArtist({
    required this.id,
    required this.name,
    required this.picture,
  });
}

// Placeholder for YouTube result
class YoutubeResult {
  final String videoId;
  final String title;
  final String channelName;
  final String thumbnail;
  final Duration? duration;

  YoutubeResult({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.thumbnail,
    this.duration,
  });
}

// Placeholder for Innertube search result
class SearchResult {
  final String id;
  final String title;
  final String subtitle;
  final String thumbnail;

  SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnail,
  });
}