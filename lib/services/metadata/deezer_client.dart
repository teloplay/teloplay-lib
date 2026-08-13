import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../cache/metadata_cache_service.dart';

/// Deezer API client using official public API.
/// Rate limit: 50 req / 5 sec. Cache-first strategy.
///
/// ⚠️ Fix (Phase 0 v11 stabilization): this used to import
/// DeezerTrack/DeezerAlbum/DeezerArtist from
/// services/search/search_orchestrator.dart — that file has been
/// deleted (it was a broken, duplicate SearchOrchestrator; the real one
/// now lives in providers/search_provider.dart). Those three classes are
/// genuinely this file's own data shapes, not the orchestrator's, so
/// they're defined here now — their real home.
///
/// Also: `_appId` was stored but never actually used in any request, and
/// `_secret` was sent as `access_token` — but every endpoint this client
/// calls (search/track, search/album, search/artist, artist/:id/related)
/// is a public, keyless Deezer endpoint (confirmed against Deezer's own
/// API docs). `access_token` is only meaningful for the OAuth flow
/// (reading/writing a specific user's account), which this app never
/// does. Both fields are now optional and unused in requests — kept only
/// so a future OAuth-requiring feature has somewhere to plug in, per
/// roadmap Section J ("official public API, app registration/API key").
class DeezerClient {
  static const _baseUrl = 'https://api.deezer.com';
  final String? _appId;
  final String? _secret;
  final MetadataCacheService _cache;

  DeezerClient({
    String? appId,
    String? secret,
    required MetadataCacheService cache,
  })  : _appId = appId,
        _secret = secret,
        _cache = cache;

  /// Search tracks with cache-first + timeout safety.
  Future<List<DeezerTrack>> searchTracks(String query, {int limit = 10}) async {
    final cacheKey = 'search:$query:$limit';
    final cached = await _cache.get(source: 'deezer', type: 'search', id: cacheKey);
    if (cached != null) {
      AppLogger.search('Deezer cache hit: $cacheKey');
      return (cached['data'] as List).map((j) => _parseTrack(j)).toList();
    }

    try {
      final uri = Uri.parse('$_baseUrl/search/track').replace(queryParameters: {
        'q': query,
        'limit': limit.toString(),
      });

      final response = await http.get(uri).timeout(const Duration(milliseconds: 350));
      if (response.statusCode != 200) {
        throw Exception('Deezer HTTP ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final tracks = (json['data'] as List? ?? []).map((j) => _parseTrack(j)).toList();

      await _cache.set(
        source: 'deezer',
        type: 'search',
        id: cacheKey,
        data: json,
        ttl: const Duration(days: 7),
      );

      return tracks;
    } catch (e) {
      AppLogger.error('Deezer search failed: $e');
      return [];
    }
  }

  /// Search albums.
  Future<List<DeezerAlbum>> searchAlbums(String query, {int limit = 10, int offset = 0}) async {
    try {
      final uri = Uri.parse('$_baseUrl/search/album').replace(queryParameters: {
        'q': query,
        'limit': limit.toString(),
        'index': offset.toString(),
      });

      final response = await http.get(uri).timeout(const Duration(milliseconds: 350));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      return (json['data'] as List? ?? []).map((j) => DeezerAlbum(
        id: j['id'].toString(),
        name: j['title'] ?? '',
        artistName: j['artist']?['name'] ?? '',
        cover: j['cover_medium'] ?? j['cover'] ?? '',
      )).toList();
    } catch (e) {
      AppLogger.error('Deezer album search failed: $e');
      return [];
    }
  }

  /// Search artists.
  Future<List<DeezerArtist>> searchArtists(String query, {int limit = 10, int offset = 0}) async {
    try {
      final uri = Uri.parse('$_baseUrl/search/artist').replace(queryParameters: {
        'q': query,
        'limit': limit.toString(),
        'index': offset.toString(),
      });

      final response = await http.get(uri).timeout(const Duration(milliseconds: 350));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      return (json['data'] as List? ?? []).map((j) => DeezerArtist(
        id: j['id'].toString(),
        name: j['name'] ?? '',
        picture: j['picture_medium'] ?? j['picture'] ?? '',
      )).toList();
    } catch (e) {
      AppLogger.error('Deezer artist search failed: $e');
      return [];
    }
  }

  /// Get similar artists (Discovery Layer 3 — instant path).
  Future<List<DeezerArtist>> getSimilarArtists(String artistId) async {
    try {
      final uri = Uri.parse('$_baseUrl/artist/$artistId/related');
      final response = await http.get(uri).timeout(const Duration(milliseconds: 350));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      return (json['data'] as List? ?? []).map((j) => DeezerArtist(
        id: j['id'].toString(),
        name: j['name'] ?? '',
        picture: j['picture_medium'] ?? '',
      )).toList();
    } catch (e) {
      AppLogger.error('Deezer similar artists failed: $e');
      return [];
    }
  }

  DeezerTrack _parseTrack(dynamic json) => DeezerTrack(
        id: json['id'].toString(),
        title: json['title'] ?? '',
        artistName: json['artist']?['name'] ?? '',
        albumName: json['album']?['title'],
        albumCover: json['album']?['cover_medium'] ?? json['album']?['cover'],
        duration: json['duration'] != null
            ? Duration(seconds: json['duration'] as int)
            : null,
      );
}

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
