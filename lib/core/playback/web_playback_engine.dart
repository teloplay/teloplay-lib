import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env_config.dart';
import '../logging/app_logger.dart';
import 'playback_engine.dart';

/// Web playback engine.
///
/// Browser/Web cannot run the existing Android MethodChannel/Kotlin bridge or
/// the Windows innertube-cli.jar daemon. For the web target this engine talks
/// only to our own stream server (Render: `TELOPLAY_STREAM_PROXY_URL`):
///
///   GET /api/search?q=&limit=  -> {ok, results:[{videoId,title,author,thumbnail,duration(sec),...}]}
///   GET /api/suggest?q=        -> {ok, suggestions:[...]}
///   GET /api/resolve?id=       -> {ok, provider, url/directUrl, ...}
///   GET /api/stream/:id        -> range-capable audio proxy fallback
///
/// ponytail: no fallback to public Piped instances. If our server is down,
/// web search/playback fails loudly instead of silently degrading to
/// third-party servers (privacy + reliability: those instances are mostly
/// dead/slow). Upgrade path: re-add a self-hosted fallback here if needed.
class WebPlaybackEngine implements PlaybackEngine {
  WebPlaybackEngine({
    http.Client? httpClient,
    String? proxyBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _proxyBaseOverride = proxyBaseUrl;

  final http.Client _httpClient;
  final String? _proxyBaseOverride;

  /// Ager web_app ApiService-er hardcoded default (lib/web_app/services/
  /// api_service.dart). .env miss/load-fail holeo web jeno more na jay.
  static const _defaultProxyBase = 'https://teloplay-stream-service.teloplay-verify.workers.dev';

  @override
  String get engineLabel => 'teloplay-web';

  @override
  Future<void> initialize() async {
    AppLogger.playback('[$engineLabel] ready (proxy=$_proxyBase)');
  }

  String get _proxyBase {
    final fromEnv = (_proxyBaseOverride ?? EnvConfig.streamProxyUrl).trim();
    final base = fromEnv.isEmpty ? _defaultProxyBase : fromEnv;
    return base.replaceAll(RegExp(r'/$'), '');
  }

  @override
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    AppLogger.playback('[$engineLabel] search: $trimmed (limit=$limit)');

    try {
      final uri = Uri.parse('$_proxyBase/api/search').replace(
        queryParameters: {'q': trimmed, 'limit': '$limit'},
      );
      final decoded = await _getJson(uri, timeout: const Duration(seconds: 15));
      // Worker returns {ok:true, results:[...]} (see worker/worker.js).
      if (decoded is! Map || decoded['ok'] != true) {
        throw PlaybackEngineException(
          'Web search ব্যর্থ — server ok=false: ${decoded is Map ? decoded['error'] ?? 'unknown' : 'bad-shape'}',
        );
      }
      final items = decoded['results'];
      if (items is! List) return const [];
      final results = <SearchResult>[];
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final videoId = (item['videoId'] ?? item['id'] ?? '').toString();
        if (videoId.isEmpty) continue;
        // Worker search items are rich (artists[], album{name,id}, explicit)
        // — same keys as the native engines, verified live.
        final rawNames = item['allArtistNames'];
        final rawIds = item['allArtistIds'];
        final artistsList = item['artists'];
        List<String> names = const [];
        List<String?> ids = const [];
        if (rawNames is List) {
          names = rawNames.map((e) => e.toString()).toList();
        } else if (artistsList is List) {
          names = artistsList
              .map((a) => a is Map ? (a['name'] as String? ?? '') : '$a')
              .where((s) => s.isNotEmpty)
              .toList();
        }
        if (rawIds is List) {
          ids = rawIds.map((e) => e?.toString()).toList();
        } else if (artistsList is List) {
          ids = artistsList
              .map((a) => a is Map ? (a['id'] as String?)?.toString() : null)
              .toList();
        }
        final album = item['album'];
        results.add(
          SearchResult(
            videoId: videoId,
            title: (item['title'] ?? 'Unknown').toString(),
            author: (item['author'] ?? item['artist'] ?? 'Unknown').toString(),
            thumbnail: (item['thumbnail'] ??
                    item['albumArt'] ??
                    'https://i.ytimg.com/vi/$videoId/hqdefault.jpg')
                .toString(),
            duration: _parseDuration(item['duration']),
            artistId: (item['artistId'] as String?) ??
                (ids.isNotEmpty ? ids.first : null),
            albumId: (item['albumId'] as String?) ??
                (album is Map ? (album['id'] as String?) : null),
            albumName: (item['albumName'] as String?) ??
                (album is Map
                    ? (album['name'] as String?)
                    : (album is String ? album : null)),
            allArtistNames: names,
            allArtistIds: ids,
            explicit: (item['explicit'] as bool?) ?? false,
          ),
        );
      }
      AppLogger.playback(
          '[$engineLabel] search OK via server (${results.length})');
      return results;
    } catch (e) {
      AppLogger.playback('[$engineLabel] server search failed: $e');
      throw PlaybackEngineException('Web search ব্যর্থ — server error', cause: e);
    }
  }

  @override
  Future<ResolvedStream> resolveStream(String videoId) async {
    AppLogger.playback('[$engineLabel] resolveStream: $videoId');

    // Ager web_app ApiService.resolveStreamUrl-er moto: 45s timeout, karon
    // cold exact-video converter-e 15-35s lagte pare.
    try {
      final uri = Uri.parse('$_proxyBase/api/resolve').replace(
        queryParameters: {'id': videoId},
      );
      final decoded = await _getJson(uri, timeout: const Duration(seconds: 45));
      if (decoded is Map && decoded['ok'] == true) {
        final direct = (decoded['directUrl'] as String?)?.isNotEmpty == true
            ? decoded['directUrl'] as String
            : (decoded['url'] as String? ?? '');
        if (direct.isNotEmpty) {
          final provider = (decoded['provider'] as String?) ?? 'server';
          AppLogger.playback('[$engineLabel] resolved OK via server ($provider)');

          // ⚠️ Browser-e direct CDN URL play kore na — verified:
          //   1. media-CDN (savenow/loader.to) link `302` kore ekta HTML ad
          //      page-e pathay → <audio src=...> "no supported source" →
          //      progress 0:00/0:00, kono sound na (ei bug-i chilo).
          //   2. innertube googlevideo link worker-er server IP-er against
          //      signed — browser-er nijer IP theke `403`.
          // Server-er nijer /api/stream proxy Referer (`Referer: loader.to`)
          // set kore, CORS dey, ar Range forward kore — verified 200 +
          // `Content-Type: audio/mpeg` + asol MP3 bytes. Tai sheTai
          // primary streamUrl.
          // ponytail: ei path-e audio bytes Render diye jay (bandwidth cost).
          // Upgrade path: per-client signed direct URL (client-IP resolve) —
          // tab direct-e phere jaoa jabe, zero-bandwidth abar cholbe.
          return ResolvedStream(
            streamUrl: '$_proxyBase/api/stream/$videoId',
            fallbackStreamUrl: direct,
            expiresIn: const Duration(hours: 5),
            sourceLabel: 'teloplay-server/$provider',
          );
        }
      }
      final err = decoded is Map ? decoded['error'] ?? 'unknown' : 'bad-shape';
      throw PlaybackEngineException('Web resolve ব্যর্থ — server: $err');
    } catch (e) {
      AppLogger.playback('[$engineLabel] server resolve failed: $e');
      if (e is PlaybackEngineException) rethrow;
      throw PlaybackEngineException('Web resolve ব্যর্থ — server error',
          cause: e);
    }
  }

  Future<Object?> _getJson(Uri uri, {required Duration timeout}) async {
    final response = await _httpClient.get(
      uri,
      headers: const {'Accept': 'application/json, text/plain, */*'},
    ).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlaybackEngineException('HTTP ${response.statusCode} $uri');
    }
    final body = response.body.trim();
    if (body.isEmpty || body.startsWith('<')) {
      throw PlaybackEngineException('Non-JSON response from $uri');
    }
    return jsonDecode(body);
  }

  Duration? _parseDuration(Object? value) {
    if (value == null) return null;
    if (value is int) return Duration(seconds: value);
    if (value is num) return Duration(seconds: value.toInt());

    final text = value.toString().trim();
    final asInt = int.tryParse(text);
    if (asInt != null) return Duration(seconds: asInt);

    final parts = text.split(':').map((p) => int.tryParse(p) ?? 0).toList();
    if (parts.length == 2) {
      return Duration(minutes: parts[0], seconds: parts[1]);
    }
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return null;
  }

  @override
  Future<List<String>> searchSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // Tomar server: GET /api/suggest?q= -> {ok, suggestions:[...]}
    // (see worker/worker.js + ager web_app ApiService.getSuggestions).
    try {
      final uri = Uri.parse('$_proxyBase/api/suggest').replace(
        queryParameters: {'q': trimmed},
      );
      final decoded =
          await _getJson(uri, timeout: const Duration(seconds: 6));
      if (decoded is Map) {
        final list = decoded['suggestions'];
        if (list is List) {
          return list
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  // ───────────────────────────────────────────────────────────────────────
  // Rich catalog (wired to the stream worker — all endpoints verified live).
  // ───────────────────────────────────────────────────────────────────────

  /// Typed multi-entity sections via /api/search-filter
  /// (song | album | artist | playlist). One filter failing never fails
  /// the whole search — that section is skipped, like the native engines.
  @override
  Future<List<SearchSection>> searchSections(
    String query, {
    int limitPerSection = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final limit = limitPerSection <= 0 ? 25 : limitPerSection;
    const filters = <String, String>{
      'song': 'Songs',
      'album': 'Albums',
      'artist': 'Artists',
      'playlist': 'Playlists',
    };
    final sections = <SearchSection>[];
    for (final entry in filters.entries) {
      try {
        final uri = Uri.parse('$_proxyBase/api/search-filter').replace(
          queryParameters: {
            'query': trimmed,
            'filter': entry.key,
            'limit': '$limit',
          },
        );
        final decoded =
            await _getJson(uri, timeout: const Duration(seconds: 15));
        if (decoded is! Map || decoded['ok'] != true) continue;
        final raw = decoded['results'];
        if (raw is! List) continue;
        final items = <RichSearchItem>[];
        for (final e in raw) {
          if (e is! Map) continue;
          final item =
              RichSearchItem.fromJson(e.cast<String, dynamic>());
          if (item.id.isEmpty) continue;
          items.add(item);
        }
        if (items.isNotEmpty) {
          sections.add(SearchSection(title: entry.value, items: items));
        }
      } catch (_) {
        continue;
      }
    }
    if (sections.isEmpty) {
      // Fallback: song-only section from /api/search (old behavior).
      final songLimit = limitPerSection <= 0 ? 25 : limitPerSection;
      final songs = await search(query, limit: songLimit);
      if (songs.isEmpty) return const [];
      return [
        SearchSection(
          title: 'Songs',
          items: songs
              .map((s) => RichSearchItem(
                    type: 'song',
                    id: s.videoId,
                    title: s.title,
                    thumbnail: s.thumbnail,
                    subtitle: s.author,
                    duration: s.duration,
                  ))
              .toList(),
        ),
      ];
    }
    return sections;
  }

  @override
  Future<SearchSuggestions> searchSuggestionsRich(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const SearchSuggestions();
    try {
      final uri = Uri.parse('$_proxyBase/api/suggest').replace(
        queryParameters: {'q': trimmed},
      );
      final decoded =
          await _getJson(uri, timeout: const Duration(seconds: 6));
      if (decoded is! Map) return const SearchSuggestions();
      final queries = <String>[];
      final q = decoded['queries'];
      if (q is List) {
        queries.addAll(
            q.map((e) => e.toString()).where((e) => e.trim().isNotEmpty));
      } else {
        queries.addAll(await searchSuggestions(trimmed));
      }
      final items = <RichSearchItem>[];
      for (final key in ['recommendedItems', 'recommended']) {
        final rec = decoded[key];
        if (rec is List) {
          for (final e in rec) {
            if (e is! Map) continue;
            final item =
                RichSearchItem.fromJson(e.cast<String, dynamic>());
            if (item.id.isEmpty) continue;
            items.add(item);
          }
          if (items.isNotEmpty) break;
        }
      }
      return SearchSuggestions(queries: queries, items: items);
    } catch (_) {
      return const SearchSuggestions();
    }
  }

  Future<Map<String, dynamic>?> _getMap(String path,
      Map<String, String> params, {
        Duration timeout = const Duration(seconds: 15),
      }) async {
    try {
      final uri =
          Uri.parse('$_proxyBase$path').replace(queryParameters: params);
      final decoded = await _getJson(uri, timeout: timeout);
      if (decoded is Map && decoded['ok'] == true) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getAlbum(String albumId) =>
      _getMap('/api/album', {'id': albumId});

  @override
  Future<Map<String, dynamic>?> getArtist(String artistId,
          {int limit = 0}) =>
      _getMap('/api/artist', {
        'id': artistId,
        if (limit > 0) 'limit': '$limit',
      });

  @override
  Future<List<SearchResult>> getRelatedTracks(String videoId,
      {int limit = 20}) async {
    final map = await _getMap('/api/song', {'id': videoId});
    final raw = map?['relatedSongs'];
    if (raw is! List) return const [];
    final results = <SearchResult>[];
    for (final e in raw.take(limit)) {
      if (e is! Map) continue;
      final item = RichSearchItem.fromJson(e.cast<String, dynamic>());
      if (!item.isSong || item.id.isEmpty) continue;
      results.add(
        SearchResult(
          videoId: item.id,
          title: item.title,
          author: item.subtitle ?? 'Unknown',
          thumbnail: item.thumbnail.isEmpty
              ? 'https://i.ytimg.com/vi/${item.id}/hqdefault.jpg'
              : item.thumbnail,
          duration: item.duration,
          explicit: item.explicit,
        ),
      );
    }
    return results;
  }

  @override
  Future<Map<String, dynamic>?> getPlaylist(String playlistId,
          {int limit = 0}) =>
      _getMap('/api/playlist', {
        'id': playlistId,
        if (limit > 0) 'limit': '$limit',
      });

  @override
  Future<Map<String, dynamic>?> getExplore() =>
      _getMap('/api/home', {});

  @override
  Future<Map<String, dynamic>?> getChartsData() =>
      _getMap('/api/charts', {});

  @override
  Future<String?> getLyricsText(String videoId) async {
    // Worker accepts id-only (YTM description path); title/artist only
    // improve the LRCLib fallback. Engine interface carries videoId only.
    final map = await _getMap('/api/lyrics', {'id': videoId});
    final plain = map?['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) return plain;
    return null;
  }

  @override
  Stream<AudioFocusSignal>? get audioFocusStream => null;

  @override
  Stream<String?>? get connectedAudioDeviceStream => null;

  @override
  Stream<double>? get bufferHealthStream => null;

  @override
  Future<void> onAudioFocusLost() async {}

  @override
  Future<void> onAudioFocusGained() async {}

  @override
  Future<void> dispose() async {
    _httpClient.close();
  }
}
