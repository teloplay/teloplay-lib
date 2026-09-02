import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Configurable base URL - default to local or your Cloudflare Worker
  String _baseUrl = 'https://teloplay-api.onrender.com';

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _log('CONFIG', 'Base URL set to: $_baseUrl');
  }

  // â”€â”€â”€ Error Logger â”€â”€â”€
  static final List<Map<String, dynamic>> _errorLog = [];
  static const int _maxLog = 100;

  static void _log(String tag, String msg, [Object? error]) {
    final entry = {
      'ts': DateTime.now().toIso8601String(),
      'tag': tag,
      'msg': msg,
      if (error != null) 'error': error.toString(),
    };
    _errorLog.add(entry);
    if (_errorLog.length > _maxLog) _errorLog.removeAt(0);

    if (error != null) {
      debugPrint('âŒ [$tag] $msg | Error: $error');
    } else {
      debugPrint('ðŸ“¡ [$tag] $msg');
    }
  }

  /// Get all logged errors (for UI display)
  static List<Map<String, dynamic>> get errorLog => List.unmodifiable(_errorLog);

  /// Clear error log
  static void clearLog() => _errorLog.clear();

  /// Search tracks by query
  Future<List<Track>> searchTracks(String query, {int limit = 50}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      _log('SEARCH', 'Searching "$cleanQuery" (limit: $limit)');

      final uri = Uri.parse('$_baseUrl/api/search').replace(queryParameters: {
        'q': cleanQuery,
        'limit': limit.toString(),
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] != true) {
          _log('SEARCH', 'Server returned ok=false: ${data['error']}', data['error']);
          return [];
        }
        final list = data['results'] as List? ?? [];
        _log('SEARCH', 'Found ${list.length} tracks for "$cleanQuery"');
        return list.map((item) => Track.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        final bodyPreview = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
        _log('SEARCH', 'HTTP ${response.statusCode}', 'Status: ${response.statusCode} Body: $bodyPreview');
      }
    } catch (e) {
      _log('SEARCH', 'Exception searching "$cleanQuery"', e);
    }
    return [];
  }

  /// Get search suggestions
  Future<List<String>> getSuggestions(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final uri = Uri.parse('$_baseUrl/api/suggest').replace(queryParameters: {
        'q': cleanQuery,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['suggestions'] as List? ?? [];
        return list.map((e) => e.toString()).toList();
      } else {
        _log('SUGGEST', 'HTTP ${response.statusCode}');
      }
    } catch (e) {
      _log('SUGGEST', 'Exception for "$cleanQuery"', e);
    }
    return [];
  }

  /// Resolve stream URL for a given video ID
  Future<String?> resolveStreamUrl(String videoId) async {
    if (videoId.isEmpty) return null;

    try {
      _log('RESOLVE', 'Resolving stream for $videoId');

      final uri = Uri.parse('$_baseUrl/api/resolve').replace(queryParameters: {
        'id': videoId,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['url'] != null) {
          _log('RESOLVE', 'OK: itag=${data['itag']} for $videoId');
          return data['url'] as String;
        } else {
          _log('RESOLVE', 'Failed: ${data['error']}', data['error']);
        }
      } else {
        _log('RESOLVE', 'HTTP ${response.statusCode}', response.body);
      }
    } catch (e) {
      _log('RESOLVE', 'Exception resolving $videoId', e);
    }

    // Do not return the proxy URL after a resolver failure. The proxy calls
    // the same resolver again and only hides the actual YouTube error.
    _log('RESOLVE', 'No playable stream returned for $videoId');
    return null;
  }

  /// Get trending / top music hits
  Future<List<Track>> getTrending() async {
    final tracks = await searchTracks('Trending Hits Top Music 2026', limit: 20);
    if (tracks.isNotEmpty) return tracks;
    return await searchTracks('Popular Songs', limit: 20);
  }

  /// Fetch errors from the worker's /api/errors
  Future<List<Map<String, dynamic>>> getServerErrors() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/errors');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['errors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (e) {
      _log('SERVER_ERRORS', 'Failed to fetch', e);
    }
    return [];
  }
}


