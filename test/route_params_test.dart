import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/playback/playback_engine.dart';
import 'package:teloplay/providers/app_router.dart' show
    shellTabNames,
    shellTabIndexForParam,
    seeAllLocation,
    songTrackFromExtra;
import 'package:teloplay/providers/search_provider.dart' show SearchCategory;

/// P0 routing pins: tab addressing, See-All URL contract, extra forwarding.
/// Pure helpers — no widgets, no seams.
void main() {
  group('shellTabIndexForParam', () {
    test('maps the four tabs in shell order', () {
      expect(shellTabNames, ['home', 'search', 'library', 'profile']);
      expect(shellTabIndexForParam('home'), 0);
      expect(shellTabIndexForParam('search'), 1);
      expect(shellTabIndexForParam('library'), 2);
      expect(shellTabIndexForParam('profile'), 3);
    });

    test('unknown/absent tab falls back to home', () {
      expect(shellTabIndexForParam(null), 0);
      expect(shellTabIndexForParam(''), 0);
      expect(shellTabIndexForParam('nope'), 0);
      expect(shellTabIndexForParam('HOME'), 0);
    });
  });

  group('seeAllLocation', () {
    test('encodes query and category for the builder contract', () {
      final loc = seeAllLocation('arijit singh', SearchCategory.songs);
      expect(loc.startsWith('/search/category?'), isTrue);
      expect(loc, contains('q=arijit%20singh'));
      expect(loc, contains('category=songs'));
      // Builder reads queryParameters — parse back to prove round-trip.
      final uri = Uri.parse(loc);
      expect(uri.queryParameters['q'], 'arijit singh');
      expect(uri.queryParameters['category'], 'songs');
    });

    test('encodes reserved characters', () {
      final loc = seeAllLocation('a&b=c?d', SearchCategory.albums);
      expect(Uri.parse(loc).queryParameters['q'], 'a&b=c?d');
    });
  });

  group('songTrackFromExtra', () {
    SearchResult track() => const SearchResult(
          videoId: 'v1',
          title: 't',
          author: 'a',
          thumbnail: '',
        );

    test('passes SearchResult through', () {
      final t = track();
      expect(songTrackFromExtra(t), same(t));
    });

    test('bare deep links (null/foreign extra) yield null', () {
      expect(songTrackFromExtra(null), isNull);
      expect(songTrackFromExtra('song-id-string'), isNull);
      expect(songTrackFromExtra({'videoId': 'v1'}), isNull);
    });
  });
}
