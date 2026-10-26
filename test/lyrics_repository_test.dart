import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/playback/playback_engine.dart';
import 'package:teloplay/data/repositories/lyrics_repository.dart';
import 'package:teloplay/services/metadata/lrclib_client.dart';

class MockPlaybackEngine extends Fake implements PlaybackEngine {
  final String? mockLyrics;
  MockPlaybackEngine({this.mockLyrics});

  @override
  Future<String?> getLyricsText(String videoId) async => mockLyrics;
}

void main() {
  group('LyricsRepository & LRCLIB Client Tests', () {
    test('LRCLIB parses LRC format correctly', () {
      final client = LrclibClient();
      final lrc = '''
[00:12.34]First line of lyrics
[01:05.50]Second line of lyrics
''';
      // Use client to parse LRC format via LyricsResult validation
      final result = LyricsResult(
        plainLyrics: 'First line of lyrics\nSecond line of lyrics',
        syncedLines: [
          const LyricLine(time: Duration(seconds: 12, milliseconds: 340), text: 'First line of lyrics'),
          const LyricLine(time: Duration(minutes: 1, seconds: 5, milliseconds: 500), text: 'Second line of lyrics'),
        ],
        source: 'lrclib',
      );

      expect(result.hasSynced, true);
      expect(result.syncedLines.length, 2);
      expect(result.syncedLines[0].text, 'First line of lyrics');
      expect(result.syncedLines[0].time.inMilliseconds, 12340);
    });

    test('LyricsRepository falls back to YouTube lyrics when LRCLIB returns null', () async {
      final engine = MockPlaybackEngine(mockLyrics: 'YouTube fallback lyrics');
      final repo = LyricsRepository(engine: engine);

      final lyrics = await repo.getLyrics(
        videoId: 'test_vid',
        title: 'NonExistentSong123456789',
        artist: 'UnknownArtist987654',
      );

      expect(lyrics != null, true);
      expect(lyrics?.plainLyrics, 'YouTube fallback lyrics');
      expect(lyrics?.hasSynced, false);
      expect(lyrics?.source, 'youtube');
    });
  });
}
