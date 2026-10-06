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
  static const _defaultProxyBase = 'https://teloplay-web.onrender.com';

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
  // Contract-compatibility members (PlaybackEngine gained these after this
  // engine was last updated). Each returns the base class's own documented
  // neutral fallback — the same value Android/Windows return on failure —
  // because the web data path does not expose the underlying catalog data:
  // the worker/ApiService surface has no album/artist/playlist/explore/
  // charts/related/lyrics endpoint, and the web playback stack resolves
  // streams directly. Callers already handle these fallbacks (e.g.
  // LyricsRepository treats null as "no lyrics", the search orchestrator
  // builds song-only sections from [] via sectionsOrFallback).
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<List<SearchSection>> searchSections(
    String query, {
    int limitPerSection = 20,
  }) async {
    // SearchController "NO LIMIT" bojhate limitPerSection=0 pathay (native
    // daemon-er convention). Worker /api/search-e limit=0 gele clamp hoye 1
    // hoye jay (Math.max(limit,1)) — tai screenshot-er moto 1 ta result asto.
    // Web-e 0-ke sane default 25-e map kora holo.
    final limit = limitPerSection <= 0 ? 25 : limitPerSection;
    final songs = await search(query, limit: limit);
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

  @override
  Future<SearchSuggestions> searchSuggestionsRich(String query) async =>
      // Base-class default: suggestion previews are non-critical; the
      // text-only searchSuggestions() above remains available.
      const SearchSuggestions();

  @override
  Future<Map<String, dynamic>?> getAlbum(String albumId) async => null;

  @override
  Future<Map<String, dynamic>?> getArtist(String artistId,
          {int limit = 0}) async =>
      null;

  @override
  Future<List<SearchResult>> getRelatedTracks(String videoId,
          {int limit = 20}) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> getPlaylist(String playlistId,
          {int limit = 0}) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getExplore() async => null;

  @override
  Future<Map<String, dynamic>?> getChartsData() async => null;

  @override
  Future<String?> getLyricsText(String videoId) async => null;

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
