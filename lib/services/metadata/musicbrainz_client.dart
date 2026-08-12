import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../cache/metadata_cache_service.dart';

/// MusicBrainz API client — BACKGROUND/NIGHTLY ONLY.
/// Rate limit: 1 req/sec strict. Sequential queue required.
/// User-Agent header mandatory.
class MusicBrainzClient {
  static const _baseUrl = 'https://musicbrainz.org/ws/2';
  final String _appName;
  final String _appVersion;
  final String _contactEmail;
  final MetadataCacheService _cache;

  MusicBrainzClient({
    required String appName,
    required String appVersion,
    required String contactEmail,
    required MetadataCacheService cache,
  })  : _appName = appName,
        _appVersion = appVersion,
        _contactEmail = contactEmail,
        _cache = cache;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': '$_appName/$_appVersion ($_contactEmail)',
  };

  /// Search artist by name — background only.
  Future<List<MusicBrainzArtist>> searchArtist(String name) async {
    final cacheKey = 'artist:${name.toLowerCase()}';
    final cached = await _cache.get(source: 'musicbrainz', type: 'artist', id: cacheKey);
    if (cached != null) {
      return (cached['artists'] as List? ?? []).map((j) => _parseArtist(j)).toList();
    }

    try {
      final uri = Uri.parse('$_baseUrl/artist').replace(queryParameters: {
        'query': 'artist:$name',
        'fmt': 'json',
        'limit': '10',
      });

      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      final artists = (json['artists'] as List? ?? [])
          .map((j) => _parseArtist(j))
          .toList();

      await _cache.set(
        source: 'musicbrainz',
        type: 'artist',
        id: cacheKey,
        data: json,
        ttl: const Duration(days: 30),
      );

      return artists;
    } catch (e) {
      AppLogger.error('MusicBrainz artist search failed: $e');
      return [];
    }
  }

  /// Get artist relationships (similar, collaborations) — background only.
  Future<List<MusicBrainzRelation>> getArtistRelations(String mbid) async {
    try {
      final uri = Uri.parse('$_baseUrl/artist/$mbid')
          .replace(queryParameters: {'fmt': 'json', 'inc': 'artist-rels'});

      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      return (json['relations'] as List? ?? []).map((r) => MusicBrainzRelation(
        type: r['type'] ?? '',
        direction: r['direction'] ?? '',
        targetName: r['artist']?['name'] ?? '',
        targetMbid: r['artist']?['id'] ?? '',
      )).toList();
    } catch (e) {
      AppLogger.error('MusicBrainz relations failed: $e');
      return [];
    }
  }

  /// ISRC cross-reference lookup — background only.
  Future<String?> lookupByIsrc(String isrc) async {
    try {
      final uri = Uri.parse('$_baseUrl/isrc/$isrc')
          .replace(queryParameters: {'fmt': 'json'});

      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final recordings = json['recordings'] as List?;
      if (recordings == null || recordings.isEmpty) return null;

      return recordings.first['id'] as String?;
    } catch (e) {
      AppLogger.error('MusicBrainz ISRC lookup failed: $e');
      return null;
    }
  }

  MusicBrainzArtist _parseArtist(dynamic json) => MusicBrainzArtist(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    sortName: json['sort-name'],
    country: json['country'],
    disambiguation: json['disambiguation'],
  );
}

class MusicBrainzArtist {
  final String id;
  final String name;
  final String? sortName;
  final String? country;
  final String? disambiguation;

  MusicBrainzArtist({
    required this.id,
    required this.name,
    this.sortName,
    this.country,
    this.disambiguation,
  });
}

class MusicBrainzRelation {
  final String type;
  final String direction;
  final String targetName;
  final String targetMbid;

  MusicBrainzRelation({
    required this.type,
    required this.direction,
    required this.targetName,
    required this.targetMbid,
  });
}