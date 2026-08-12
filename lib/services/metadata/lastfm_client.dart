import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../cache/metadata_cache_service.dart';

/// Last.fm API client — BACKGROUND ONLY, never called from UI thread.
/// Rate limit: ~0.5 req/sec sustained safe. Uses batch queue.
class LastFmClient {
  static const _baseUrl = 'https://ws.audioscrobbler.com/2.0';
  final String _apiKey;
  final MetadataCacheService _cache;

  LastFmClient({
    required String apiKey,
    required MetadataCacheService cache,
  })  : _apiKey = apiKey,
        _cache = cache;

  /// Get similar artists with match percentage.
  /// Called ONLY from background DiscoveryQueue, never UI thread.
  Future<List<LastFmSimilarArtist>> getSimilarArtists(String artistName) async {
    final cacheKey = 'similar:${artistName.toLowerCase()}';
    final cached = await _cache.get(source: 'lastfm', type: 'similar_artists', id: cacheKey);
    if (cached != null) {
      return (cached['similarartists']?['artist'] as List? ?? [])
          .map((j) => LastFmSimilarArtist(
            name: j['name'] ?? '',
            match: double.tryParse(j['match'] ?? '0') ?? 0,
            image: (j['image'] as List? ?? []).isNotEmpty
                ? j['image'].last['#text']
                : '',
          ))
          .toList();
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'method': 'artist.getSimilar',
        'artist': artistName,
        'api_key': _apiKey,
        'format': 'json',
        'limit': '20',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      final artists = (json['similarartists']?['artist'] as List? ?? [])
          .map((j) => LastFmSimilarArtist(
            name: j['name'] ?? '',
            match: double.tryParse(j['match'] ?? '0') ?? 0,
            image: (j['image'] as List? ?? []).isNotEmpty
                ? j['image'].last['#text']
                : '',
          ))
          .toList();

      await _cache.set(
        source: 'lastfm',
        type: 'similar_artists',
        id: cacheKey,
        data: json,
        ttl: const Duration(days: 30),
      );

      return artists;
    } catch (e) {
      AppLogger.error('Last.fm similar artists failed: $e');
      return [];
    }
  }

  /// Get artist tags (genres).
  Future<List<String>> getArtistTags(String artistName) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'method': 'artist.getTopTags',
        'artist': artistName,
        'api_key': _apiKey,
        'format': 'json',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      return (json['toptags']?['tag'] as List? ?? [])
          .take(5)
          .map((t) => t['name'] as String)
          .toList();
    } catch (e) {
      AppLogger.error('Last.fm tags failed: $e');
      return [];
    }
  }

  /// Get trending tracks (background enrichment).
  Future<List<LastFmTrack>> getTrendingTracks({String? country}) async {
    try {
      final params = {
        'method': 'chart.getTopTracks',
        'api_key': _apiKey,
        'format': 'json',
        'limit': '50',
      };
      if (country != null) params['country'] = country;

      final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      return (json['tracks']?['track'] as List? ?? []).map((j) => LastFmTrack(
        name: j['name'] ?? '',
        artist: j['artist']?['name'] ?? '',
        image: (j['image'] as List? ?? []).isNotEmpty
            ? j['image'].last['#text']
            : '',
      )).toList();
    } catch (e) {
      AppLogger.error('Last.fm trending failed: $e');
      return [];
    }
  }
}

class LastFmSimilarArtist {
  final String name;
  final double match;
  final String? image;
  LastFmSimilarArtist({required this.name, required this.match, this.image});
}

class LastFmTrack {
  final String name;
  final String artist;
  final String? image;
  LastFmTrack({required this.name, required this.artist, this.image});
}