import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teloplay/core/playback/playback_engine.dart';
import 'package:teloplay/core/playback/web_playback_engine.dart';

/// WebPlaybackEngine server-contract check — tomar Render server-er real
/// shape ({ok,results}/{ok,suggestions}/{ok,directUrl}) parse hoy kina.
/// Run: flutter test test/web_playback_engine_test.dart
void main() {
  MockClient clientFor(Map<String, Object?> json, {int status = 200}) {
    return MockClient((_) async => http.Response(jsonEncode(json), status));
  }

  group('WebPlaybackEngine — teloplay-web server contract', () {
    test('search() parses {ok:true, results:[...]} (worker shape)', () async {
      final engine = WebPlaybackEngine(
        httpClient: clientFor({
          'ok': true,
          'results': [
            {
              'videoId': 'NJAv_7lHUIU',
              'title': 'Kesariya',
              'author': 'Arijit Singh',
              'thumbnail': 'https://i.ytimg.com/vi/NJAv_7lHUIU/hq720.jpg',
              'duration': 269,
            },
          ],
        }),
        proxyBaseUrl: 'https://example.test',
      );
      final results = await engine.search('kesariya');
      expect(results, hasLength(1));
      expect(results.first.videoId, 'NJAv_7lHUIU');
      expect(results.first.author, 'Arijit Singh');
      // Worker duration second-int -> Duration
      expect(results.first.duration, const Duration(seconds: 269));
      engine.dispose();
    });

    test('search() throws loudly on ok=false (no silent Piped fallback)',
        () async {
      final engine = WebPlaybackEngine(
        httpClient: clientFor({'ok': false, 'error': 'down'}),
        proxyBaseUrl: 'https://example.test',
      );
      expect(() => engine.search('x'), throwsA(isA<PlaybackEngineException>()));
      engine.dispose();
    });

    test('searchSuggestions() parses {suggestions:[...]}', () async {
      final engine = WebPlaybackEngine(
        httpClient:
            clientFor({'ok': true, 'suggestions': ['kesariya', 'kesariya lofi']}),
        proxyBaseUrl: 'https://example.test',
      );
      final s = await engine.searchSuggestions('kes');
      expect(s, ['kesariya', 'kesariya lofi']);
      engine.dispose();
    });

    test('searchSections(limitPerSection: 0) maps to 25, not 1', () async {
      final seenLimits = <String>[];
      final engine = WebPlaybackEngine(
        httpClient: MockClient((req) async {
          seenLimits.add(req.url.queryParameters['limit'] ?? '');
          // Filter-aware mock: typed item per /api/search-filter filter.
          final filter = req.url.queryParameters['filter'] ?? 'song';
          final item = switch (filter) {
            'album' => {
                'type': 'album',
                'albumId': 'MPREb_test',
                'title': 'Kesariya Album',
                'thumbnail': 'a.jpg',
              },
            'artist' => {
                'type': 'artist',
                'artistId': 'UCtest',
                'title': 'Arijit Singh',
                'thumbnail': 'r.jpg',
              },
            'playlist' => {
                'type': 'playlist',
                'playlistId': 'PLtest',
                'title': 'Kesariya Mix',
                'thumbnail': 'p.jpg',
              },
            _ => {
                'type': 'song',
                'videoId': 'NJAv_7lHUIU',
                'title': 'Kesariya',
                'author': 'Arijit Singh',
                'thumbnail': 't.jpg',
                'duration': 269,
              },
          };
          return http.Response(
            jsonEncode({'ok': true, 'results': [item]}),
            200,
          );
        }),
        proxyBaseUrl: 'https://example.test',
      );
      final sections = await engine.searchSections('kesariya', limitPerSection: 0);
      // 0-kе 25-e map kora holo (worker limit=0 -> 1 hoy).
      expect(seenLimits, everyElement('25'));
      expect(sections.map((s) => s.title),
          ['Songs', 'Albums', 'Artists', 'Playlists']);
      expect(sections.first.items.first.id, 'NJAv_7lHUIU');
      expect(sections.first.items.first.subtitle, 'Arijit Singh');
      engine.dispose();
    });

    test('resolveStream() uses directUrl + sets /api/stream fallback',
        () async {
      final engine = WebPlaybackEngine(
        httpClient: clientFor({
          'ok': true,
          'provider': 'media_cdn_exact_video',
          'directUrl': 'https://cdn.example/x.mp3',
        }),
        proxyBaseUrl: 'https://example.test',
      );
      final r = await engine.resolveStream('NJAv_7lHUIU');
      // streamUrl = proxy (browser-playable); direct CDN ad-redirect koray
      // primary hisebe use kora jay na.
      expect(r.streamUrl, 'https://example.test/api/stream/NJAv_7lHUIU');
      expect(r.fallbackStreamUrl, 'https://cdn.example/x.mp3');
      expect(r.sourceLabel, contains('media_cdn_exact_video'));
      engine.dispose();
    });
  });
}
