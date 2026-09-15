import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/logging/app_logger.dart';

/// Supported AI Providers
enum AIProvider {
  groq,
  gemini,
  openrouter,
  deepseek,
  custom,
}

/// Remote AI Configuration fetched from Supabase
class AIConfig {
  final bool isEnabled;
  final AIProvider provider;
  final String model;
  final List<String> apiKeys;
  final int maxTokens;
  final double temperature;

  const AIConfig({
    this.isEnabled = true,
    this.provider = AIProvider.groq,
    this.model = 'llama-3.3-70b-versatile',
    this.apiKeys = const [],
    this.maxTokens = 600,
    this.temperature = 0.7,
  });

  factory AIConfig.fromMap(Map<String, dynamic> map) {
    final providerStr = (map['active_provider'] as String?)?.toLowerCase() ?? 'groq';
    final provider = switch (providerStr) {
      'gemini' => AIProvider.gemini,
      'openrouter' => AIProvider.openrouter,
      'deepseek' => AIProvider.deepseek,
      _ => AIProvider.groq,
    };

    final rawKeys = map['api_keys'];
    final keys = <String>[];
    if (rawKeys is List) {
      keys.addAll(rawKeys.map((e) => e.toString()).where((k) => k.isNotEmpty));
    } else if (map['api_key'] is String && (map['api_key'] as String).isNotEmpty) {
      keys.add(map['api_key'] as String);
    }

    return AIConfig(
      isEnabled: map['is_ai_enabled'] as bool? ?? true,
      provider: provider,
      model: (map['active_model'] as String?) ?? 'llama-3.3-70b-versatile',
      apiKeys: keys,
      maxTokens: (map['max_tokens'] as int?) ?? 600,
      temperature: ((map['temperature'] as num?)?.toDouble()) ?? 0.7,
    );
  }
}


/// Service orchestrating remote-controlled AI recommendation generations
class AIService {
  static AIService? _instance;
  static AIService get instance => _instance ??= AIService._();
  AIService._();

  final http.Client _client = http.Client();
  AIConfig _config = const AIConfig();
  int _currentKeyIndex = 0;
  DateTime? _lastConfigFetchAt;

  AIConfig get config => _config;

  /// Fetch remote AI configuration from Supabase 'app_config' / 'user_settings'
  Future<void> fetchRemoteConfig() async {
    final now = DateTime.now();
    if (_lastConfigFetchAt != null && now.difference(_lastConfigFetchAt!).inMinutes < 15) {
      return;
    }

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('app_config')
          .select()
          .eq('key', 'ai_recommendations')
          .maybeSingle();

      if (response != null && response['value'] is Map<String, dynamic>) {
        _config = AIConfig.fromMap(response['value'] as Map<String, dynamic>);
        _lastConfigFetchAt = now;
        AppLogger.sync('AIService: Loaded remote config (model=${_config.model}, provider=${_config.provider.name})');
      }
    } catch (e) {
      AppLogger.sync('AIService: Remote config fetch failed (using defaults): $e');
    }
  }

  /// Generate recommended tracks based on user taste, seeds, and vibe
  Future<List<({String title, String artist})>> generateRecommendations({
    required List<String> favoriteArtists,
    required List<String> recentSongs,
    String? currentVibe,
    int count = 10,
  }) async {
    await fetchRemoteConfig();
    if (!_config.isEnabled || _config.apiKeys.isEmpty) return [];

    final prompt = _buildRecommendationPrompt(
      favoriteArtists: favoriteArtists,
      recentSongs: recentSongs,
      currentVibe: currentVibe,
      count: count,
    );

    for (var attempt = 0; attempt < _config.apiKeys.length; attempt++) {
      final apiKey = _getNextApiKey();
      try {
        final jsonResponse = await _callApi(config: _config, apiKey: apiKey, prompt: prompt);
        if (jsonResponse != null && jsonResponse.isNotEmpty) {
          final recommendations = _parseRecommendations(jsonResponse);
          if (recommendations.isNotEmpty) {
            AppLogger.playback('AIService: Generated ${recommendations.length} AI tracks successfully');
            return recommendations;
          }
        }
      } catch (e) {
        AppLogger.playback('AIService: Key attempt failed: $e. Rotating to next key...');
      }
    }

    return [];
  }

  String _getNextApiKey() {
    if (_config.apiKeys.isEmpty) return '';
    final key = _config.apiKeys[_currentKeyIndex % _config.apiKeys.length];
    _currentKeyIndex++;
    return key;
  }

  String _buildRecommendationPrompt({
    required List<String> favoriteArtists,
    required List<String> recentSongs,
    String? currentVibe,
    required int count,
  }) {
    return '''
You are a music curation expert for TeloPlay music app.
Recommend $count real, accurate songs based on the user's taste:
Favorite Artists: ${favoriteArtists.join(', ')}
Recently Played: ${recentSongs.join(', ')}
Current Context/Vibe: ${currentVibe ?? 'Neutral listening'}

Return STRICTLY a JSON array of objects with "title" and "artist" keys. No markdown codeblock, no explanation text.
Example format:
[{"title": "Kesariya", "artist": "Arijit Singh"}, {"title": "Starboy", "artist": "The Weeknd"}]
''';
  }

  List<({String title, String artist})> _parseRecommendations(String rawOutput) {
    try {
      var cleaned = rawOutput.trim();
      if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
      if (cleaned.startsWith('```')) cleaned = cleaned.substring(3);
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
      cleaned = cleaned.trim();

      final parsed = jsonDecode(cleaned);
      if (parsed is List) {
        return parsed
            .map((item) {
              if (item is Map) {
                final title = (item['title'] ?? '').toString().trim();
                final artist = (item['artist'] ?? '').toString().trim();
                if (title.isNotEmpty) return (title: title, artist: artist);
              }
              return null;
            })
            .whereType<({String title, String artist})>()
            .toList();
      }
    } catch (e) {
      AppLogger.sync('AIService: Parse error: $e');
    }
    return [];
  }

  Future<String?> _callApi({
    required AIConfig config,
    required String apiKey,
    required String prompt,
  }) async {
    final uri = switch (config.provider) {
      AIProvider.groq => Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      AIProvider.gemini => Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent?key=$apiKey'),
      AIProvider.openrouter => Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      AIProvider.deepseek => Uri.parse('https://api.deepseek.com/chat/completions'),
      _ => Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
    };

    if (config.provider == AIProvider.gemini) {
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {
            'temperature': config.temperature,
            'maxOutputTokens': config.maxTokens,
            'responseMimeType': 'application/json',
          },
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['candidates']?[0]?['content']?['parts']?[0]?['text'];
      }
      return null;
    }

    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        'HTTP-Referer': 'https://teloplay.app',
        'X-Title': 'TeloPlay Music',
      },
      body: jsonEncode({
        'model': config.model,
        'messages': [
          {
            'role': 'system',
            'content': 'You are a music recommendation assistant. Always respond with strict valid JSON array containing objects with keys "title" and "artist". No conversational text or markdown code blocks.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': config.temperature,
        'max_tokens': config.maxTokens,
      }),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['choices']?[0]?['message']?['content'];
    }
    return null;
  }
}

