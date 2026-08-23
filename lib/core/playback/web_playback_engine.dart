import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env_config.dart';
import '../logging/app_logger.dart';
import 'playback_engine.dart';

/// Web playback engine.
///
/// Browser/Web cannot run the existing Android MethodChannel/Kotlin bridge or
/// the Windows innertube-cli.jar daemon. For the web target this engine first
/// asks the configured Cloudflare Worker for an Android InnerTube-resolved URL;
/// direct googlevideo URLs avoid browser CORS restrictions and the Worker also
/// exposes a range-capable proxy fallback.
///
/// If the Worker is unavailable, the engine keeps a best-effort fallback to
/// free public Piped API instances. Those instances may occasionally be slow or
/// unavailable, so a self-hosted Worker/Piped deployment is preferable for
/// heavy production traffic.
class WebPlaybackEngine implements PlaybackEngine {
  WebPlaybackEngine({
    http.Client? httpClient,
    List<String>? apiBaseUrls,
  })  : _httpClient = httpClient ?? http.Client(),
        _apiBaseUrls = apiBaseUrls ?? _defaultApiBaseUrls;

  final http.Client _httpClient;
  final List<String> _apiBaseUrls;
  final Set<String> _deadUntil = <String>{};

  static const _defaultApiBaseUrls = <String>[
    'https://api.piped.private.coffee',
    'https://pipedapi.kavin.rocks',
    'https://pipedapi-libre.kavin.rocks',
    'https://pipedapi.leptons.xyz',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.drgns.space',
    'https://pipedapi.ducks.party',
    'https://pipedapi.reallyaweso.me',
  ];

  static const _corsProxyPrefixes = <String>[
    'https://corsproxy.io/?',
    'https://api.allorigins.win/raw?url=',
  ];

  @override
  String get engineLabel => 'piped/web';

  @override
  Future<void> initialize() async {
    final proxy = EnvConfig.streamProxyUrl.trim();
    AppLogger.playback(
      '[$engineLabel] ready (proxy=${proxy.isEmpty ? "none" : proxy})',
    );
  }

  String get _proxyBase =>
      EnvConfig.streamProxyUrl.trim().replaceAll(RegExp(r'/$'), '');

  Iterable<String> get _liveApis =>
      _apiBaseUrls.where((u) => !_deadUntil.contains(u));

  void _markDead(String baseUrl, Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('failed to fetch') ||
        text.contains('clientexception') ||
        text.contains('timeout') ||
        text.contains('403') ||
        text.contains('502') ||
        text.contains('525')) {
      _deadUntil.add(baseUrl);
    }
  }

  bool get _preferSafariAudio =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    AppLogger.playback('[$engineLabel] search: $trimmed (limit=$limit)');

    final proxyItems = await _searchViaProxy(trimmed, limit);
    if (proxyItems != null && proxyItems.isNotEmpty) return proxyItems;

    Object? lastError;
    for (final baseUrl in _liveApis) {
      try {
        final results = await _searchOnInstance(baseUrl, trimmed, limit: limit);
        if (results.isNotEmpty) {
          AppLogger.playback('[$engineLabel] search OK via $baseUrl');
          return results;
        }
      } catch (e) {
        lastError = e;
        _markDead(baseUrl, e);
        AppLogger.playback('[$engineLabel] search failed via $baseUrl: $e');
      }
    }

    throw PlaybackEngineException(
      'Web search ব্যর্থ — সব free Piped instance fail করেছে',
      cause: lastError,
    );
  }

  Future<List<SearchResult>> _searchOnInstance(
    String baseUrl,
    String query, {
    required int limit,
  }) async {
    // Try music_songs first. Some instances may not support the filter, so a
    // generic /search fallback is kept below.
    final filtered = await _requestSearch(
      baseUrl,
      query,
      limit: limit,
      filter: 'music_songs',
    );
    if (filtered.isNotEmpty) return filtered;

    return _requestSearch(baseUrl, query, limit: limit);
  }

  Future<List<SearchResult>> _requestSearch(
    String baseUrl,
    String query, {
    required int limit,
    String? filter,
  }) async {
    final uri = Uri.parse('$baseUrl/search').replace(
      queryParameters: <String, String>{
        'q': query,
        if (filter != null) 'filter': filter,
      },
    );

    final decoded = await _getJson(uri, timeout: const Duration(seconds: 8));
    final rawItems = _extractSearchItems(decoded);
    final results = <SearchResult>[];

    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();

      final url = (item['url'] ?? item['streamUrl'] ?? '').toString();
      final videoId = _extractVideoId(url);
      if (videoId == null || videoId.isEmpty) continue;

      final type = (item['type'] ?? '').toString().toLowerCase();
      if (type.isNotEmpty &&
          type != 'stream' &&
          type != 'video' &&
          type != 'music_songs' &&
          type != 'song') {
        continue;
      }

      results.add(
        SearchResult(
          videoId: videoId,
          title: (item['title'] ?? 'Unknown').toString(),
          author: (item['uploaderName'] ??
                  item['uploader'] ??
                  item['author'] ??
                  'Unknown')
              .toString(),
          thumbnail: (item['thumbnail'] ??
                  item['thumbnailUrl'] ??
                  'https://img.youtube.com/vi/$videoId/mqdefault.jpg')
              .toString(),
          duration: _parseDuration(item['duration']),
        ),
      );

      if (results.length >= limit) break;
    }

    return results;
  }

  List<dynamic> _extractSearchItems(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final items =
          decoded['items'] ?? decoded['results'] ?? decoded['relatedStreams'];
      if (items is List) return items;
    }
    return const [];
  }

  @override
  Future<ResolvedStream> resolveStream(String videoId) async {
    AppLogger.playback('[$engineLabel] resolveStream: $videoId');

    // Try 1: Worker proxy (with 1 retry)
    final proxied = await _resolveViaProxy(videoId, retry: true);
    if (proxied != null) return proxied;

    // Try 2: Direct Piped API calls from browser (some instances may work)
    for (final baseUrl in _liveApis) {
      try {
        final uri = Uri.parse('$baseUrl/streams/$videoId');
        final decoded = await _getJson(uri, timeout: const Duration(seconds: 10));
        if (decoded is! Map) continue;
        final streams = decoded['audioStreams'];
        if (streams is! List || streams.isEmpty) continue;
        // Pick best audio (prefer AAC/mp4 for Safari)
        final picked = _pickAudioStream(streams.cast<Map<String, dynamic>>());
        if (picked != null) {
          AppLogger.playback('[$engineLabel] resolved OK via direct Piped: $baseUrl');
          return picked;
        }
      } catch (e) {
        _markDead(baseUrl, e);
        AppLogger.playback('[$engineLabel] direct Piped $baseUrl fail: $e');
      }
    }

    throw PlaybackEngineException(
      'Web stream resolve ব্যর্থ — সকল source চেষ্টা করা হয়েছে। '
      'Worker /streams fail অথবা Piped API response আসছে না।',
    );
  }

  ResolvedStream? _pickAudioStream(List<Map<String, dynamic>> streams) {
    if (streams.isEmpty) return null;
    final scored = streams.where((s) => s['url'] != null).map((s) {
      final mime = (s['mimeType'] ?? '').toString().toLowerCase();
      final br = (s['bitrate'] ?? 0) is int
          ? s['bitrate'] as int
          : int.tryParse((s['bitrate'] ?? '0').toString()) ?? 0;
      final aac = mime.contains('mp4');
      final isSafari = _preferSafariAudio;
      var pts = br;
      if (isSafari) {
        pts += aac ? 10000000 : -10000000;
      } else if (aac) {
        pts += 50000;
      }
      return Map<String, dynamic>.from(s)..['_pts'] = pts;
    }).toList();

    if (scored.isEmpty) return null;
    scored.sort((a, b) => (b['_pts'] as int).compareTo(a['_pts'] as int));

    final best = scored.first;
    final url = best['url']?.toString();
    if (url == null || url.isEmpty) return null;

    return ResolvedStream(
      streamUrl: url,
      expiresIn: const Duration(hours: 2),
      sourceLabel: 'piped/direct',
    );
  }

  Future<List<SearchResult>?> _searchViaProxy(String query, int limit) async {
    if (_proxyBase.isEmpty) return null;
    try {
      final uri = Uri.parse('$_proxyBase/search').replace(
        queryParameters: {'q': query, 'limit': '$limit'},
      );
      final decoded = await _getJson(uri, timeout: const Duration(seconds: 12));
      if (decoded is! Map) return null;
      final items = decoded['items'];
      if (items is! List) return null;
      final results = <SearchResult>[];
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final videoId = (item['videoId'] ?? '').toString();
        if (videoId.isEmpty) continue;
        results.add(
          SearchResult(
            videoId: videoId,
            title: (item['title'] ?? 'Unknown').toString(),
            author: (item['author'] ?? 'Unknown').toString(),
            thumbnail: (item['thumbnail'] ??
                    'https://img.youtube.com/vi/$videoId/mqdefault.jpg')
                .toString(),
            duration: _parseDuration(item['duration']),
          ),
        );
      }
      if (results.isNotEmpty) {
        AppLogger.playback('[$engineLabel] search OK via worker');
      }
      return results;
    } catch (e) {
      AppLogger.playback('[$engineLabel] worker search failed: $e');
      return null;
    }
  }

  Future<ResolvedStream?> _resolveViaProxy(String videoId, {bool retry = false}) async {
    if (_proxyBase.isEmpty) return null;
    try {
      final safari = _preferSafariAudio ? '1' : '0';
      final uri = Uri.parse('$_proxyBase/streams/$videoId').replace(
        queryParameters: {'safari': safari},
      );
      final decoded = await _getJson(uri, timeout: const Duration(seconds: 25));
      if (decoded is! Map) return null;
      final url = decoded['streamUrl']?.toString();
      if (url == null || url.isEmpty) return null;
      AppLogger.playback('[$engineLabel] resolved OK via worker');
      return ResolvedStream(
        streamUrl: url,
        expiresIn: const Duration(hours: 5),
        sourceLabel: (decoded['sourceLabel'] ?? 'piped-worker').toString(),
      );
    } catch (e) {
      AppLogger.playback('[$engineLabel] worker resolve failed: $e');
      if (retry) {
        // Retry once after short delay
        try {
          AppLogger.playback('[$engineLabel] retrying worker resolve...');
          await Future.delayed(const Duration(milliseconds: 500));
          final safari = _preferSafariAudio ? '1' : '0';
          final uri = Uri.parse('$_proxyBase/streams/$videoId').replace(
            queryParameters: {'safari': safari},
          );
          final decoded = await _getJson(uri, timeout: const Duration(seconds: 25));
          if (decoded is! Map) return null;
          final url = decoded['streamUrl']?.toString();
          if (url == null || url.isEmpty) return null;
          AppLogger.playback('[$engineLabel] resolved OK via worker (retry)');
          return ResolvedStream(
            streamUrl: url,
            expiresIn: const Duration(hours: 5),
            sourceLabel: (decoded['sourceLabel'] ?? 'piped-worker').toString(),
          );
        } catch (retryError) {
          AppLogger.playback('[$engineLabel] worker retry also failed: $retryError');
        }
      }
      return null;
    }
  }

  Future<Object?> _getJson(
    Uri uri, {
    required Duration timeout,
    bool useCorsProxies = false,
  }) async {
    Object? lastError;

    Future<Object?> tryGet(Uri target) async {
      final response = await _httpClient.get(
        target,
        headers: const {'Accept': 'application/json, text/plain, */*'},
      ).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PlaybackEngineException('HTTP ${response.statusCode} $target');
      }
      final body = response.body.trim();
      if (body.isEmpty || body.startsWith('<')) {
        throw PlaybackEngineException('Non-JSON response from $target');
      }
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['contents'] is String) {
        return jsonDecode(decoded['contents'] as String);
      }
      return decoded;
    }

    try {
      return await tryGet(uri);
    } catch (e) {
      lastError = e;
      if (!useCorsProxies) rethrow;
    }

    for (final prefix in _corsProxyPrefixes) {
      try {
        final proxied =
            Uri.parse('$prefix${Uri.encodeComponent(uri.toString())}');
        AppLogger.playback('[$engineLabel] CORS proxy: $prefix');
        return await tryGet(proxied);
      } catch (e) {
        lastError = e;
      }
    }

    try {
      final wrapped = Uri.parse(
        'https://api.allorigins.win/get?url=${Uri.encodeComponent(uri.toString())}',
      );
      return await tryGet(wrapped);
    } catch (e) {
      lastError = e;
    }

    throw PlaybackEngineException('JSON fetch failed for $uri',
        cause: lastError);
  }

  String? _extractVideoId(String input) {
    if (input.isEmpty) return null;
    final direct = RegExp(r'^[a-zA-Z0-9_-]{11}$');
    if (direct.hasMatch(input)) return input;

    final uri = Uri.tryParse(
        input.startsWith('http') ? input : 'https://piped.video$input');
    final v = uri?.queryParameters['v'];
    if (v != null && direct.hasMatch(v)) return v;

    final match =
        RegExp(r'(?:/watch\?v=|youtu\.be/|/embed/)([a-zA-Z0-9_-]{11})')
            .firstMatch(input);
    return match?.group(1);
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

    for (final baseUrl in _liveApis) {
      try {
        final uri = Uri.parse('$baseUrl/suggestions').replace(
          queryParameters: {'query': trimmed},
        );
        final decoded =
            await _getJson(uri, timeout: const Duration(seconds: 6));
        if (decoded is List) {
          return decoded
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    return const [];
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
