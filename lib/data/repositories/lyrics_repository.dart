import '../../core/playback/playback_engine.dart';
import '../../services/metadata/lrclib_client.dart';

/// Unified Lyrics Repository combining OpenTune Innertube + LRCLIB time-synced lyrics.
class LyricsRepository {
  final PlaybackEngine _engine;
  final LrclibClient _lrclib;

  LyricsRepository({
    required PlaybackEngine engine,
    LrclibClient? lrclib,
  })  : _engine = engine,
        _lrclib = lrclib ?? LrclibClient();

  /// Gets lyrics for a song: first tries LRCLIB for time-synced lyrics,
  /// falling back to YouTube Music official plain lyrics.
  Future<LyricsResult?> getLyrics({
    required String videoId,
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    // 1. Try LRCLIB for time-synced lyrics
    final lrclibResult = await _lrclib.fetchLyrics(
      title: title,
      artist: artist,
      duration: duration,
    );

    if (lrclibResult != null && !lrclibResult.isEmpty) {
      return lrclibResult;
    }

    // 2. Fallback to YouTube Music plain lyrics via Native Engine
    try {
      final ytLyrics = await _engine.getLyricsText(videoId);
      if (ytLyrics != null && ytLyrics.isNotEmpty) {
        return LyricsResult(
          plainLyrics: ytLyrics,
          syncedLines: const [],
          source: 'youtube',
        );
      }
    } catch (_) {}

    return null;
  }
}
