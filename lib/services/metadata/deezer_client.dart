import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../cache/metadata_cache_service.dart';
import '../search/search_orchestrator.dart';

/// Deezer API client using official public API.
/// Rate limit: 50 req / 5 sec. Cache-first strategy.
class DeezerClient {
  static const _baseUrl = 'https://api.deezer.com';
  final String _appId;
  final String? _secret;
  final MetadataCacheService _cache;

  DeezerClient({
    required String appId,
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
      final uri = Uri.parse('$_baseUrl/search/track')
          .replace(queryParameters: {
        'q': query,
        'limit': limit.toString(),
        if (_secret != null) 'access_token': _secret,
      });

      final response = await http.get(uri).timeout(const Duration(milliseconds: 350));
      if (response.statusCode != 200) {
        throw Exception('Deezer HTTP ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final tracks = (json['data'] as List? ?? []).map((j) => _parseTrack(j)).toList();

      // Cache result
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