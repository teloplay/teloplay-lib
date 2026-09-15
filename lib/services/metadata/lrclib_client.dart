import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';

/// Single timestamped line in synced LRC lyrics.
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine({
    required this.time,
    required this.text,
  });
}

/// Rich Lyrics Result containing plain lyrics and parsed synchronized lines.
class LyricsResult {
  final String? plainLyrics;
  final List<LyricLine> syncedLines;
  final String source; // 'lrclib' or 'youtube'

  const LyricsResult({
    this.plainLyrics,
    this.syncedLines = const [],
    required this.source,
  });

  bool get hasSynced => syncedLines.isNotEmpty;
  bool get isEmpty => (plainLyrics == null || plainLyrics!.isEmpty) && syncedLines.isEmpty;
}

/// Official LRCLIB client providing open time-synced (LRC) lyrics.
class LrclibClient {
  static const String _baseUrl = 'https://lrclib.net/api/get';
  final http.Client _client;

  LrclibClient([http.Client? client]) : _client = client ?? http.Client();

  /// Fetches synced and plain lyrics using track title, artist name, and duration.
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    try {
      final cleanTitle = _cleanTitle(title);
      final cleanArtist = _cleanArtist(artist);
      final durationSec = duration?.inSeconds ?? 0;

      final queryParams = {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
        if (durationSec > 0) 'duration': durationSec.toString(),
      };

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      AppLogger.playback('[LRCLIB] Fetching lyrics for "$cleanTitle" by "$cleanArtist"');

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'TeloPlay/1.0.0 (https://github.com/teloplay/teloplay)',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final syncedLrc = data['syncedLyrics'] as String?;
        final plainLyrics = data['plainLyrics'] as String?;

        final lines = syncedLrc != null ? _parseLrc(syncedLrc) : <LyricLine>[];

        return LyricsResult(
          plainLyrics: plainLyrics ?? (lines.isNotEmpty ? lines.map((l) => l.text).join('\n') : null),
          syncedLines: lines,
          source: 'lrclib',
        );
      } else if (response.statusCode == 404) {
        AppLogger.playback('[LRCLIB] Lyrics not found on lrclib.net');
        return null;
      }
    } catch (e) {
      AppLogger.playback('[LRCLIB] Lyrics fetch error: $e');
    }
    return null;
  }

  /// Parses standard .lrc timestamp format: [mm:ss.xx] Text
  List<LyricLine> _parseLrc(String lrcContent) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)');

    for (final rawLine in lrcContent.split('\n')) {
      final match = regex.firstMatch(rawLine.trim());
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final secondsDouble = double.tryParse(match.group(2) ?? '0') ?? 0.0;
        final text = (match.group(3) ?? '').trim();

        final totalMs = (minutes * 60 * 1000) + (secondsDouble * 1000).toInt();
        lines.add(LyricLine(
          time: Duration(milliseconds: totalMs),
          text: text,
        ));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  String _cleanTitle(String rawTitle) {
    return rawTitle
        .replaceAll(RegExp(r'\(.*?official.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?official.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?lyrics.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?lyrics.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?video.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?hd.*?\]', caseSensitive: false), '')
        .trim();
  }

  String _cleanArtist(String rawArtist) {
    return rawArtist.split(RegExp(r'[,&•|]')).first.trim();
  }
}
