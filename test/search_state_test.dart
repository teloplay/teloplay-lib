import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/playback/playback_engine.dart';
import 'package:teloplay/models/search_models.dart';
import 'package:teloplay/providers/search_provider.dart';

/// Batch 5 — [SearchState] pure API contract (P0 search shape + P1-K
/// correction field). No providers, no I/O: construction only.
void main() {
  SearchResult song(String id) => SearchResult(
        videoId: id,
        title: 'Song $id',
        author: 'Author',
        thumbnail: '',
      );

  const album = AlbumSearchResult(albumId: 'a1', albumName: 'Album');
  const artist = ArtistSearchResult(artistId: 'r1', artistName: 'Artist');
  const playlist =
      PlaylistSearchResult(playlistId: 'p1', name: 'Mix', itemCount: 3);

  group('SearchState.isEmpty', () {
    test('default state is empty', () {
      expect(const SearchState().isEmpty, isTrue);
    });

    test('any single non-empty category clears empty', () {
      expect(SearchState(songs: [song('v1')]).isEmpty, isFalse);
      expect(const SearchState(albums: [album]).isEmpty, isFalse);
      expect(const SearchState(artists: [artist]).isEmpty, isFalse);
      expect(const SearchState(playlists: [playlist]).isEmpty, isFalse);
    });

    test('loading/error alone do not clear empty', () {
      expect(const SearchState(isLoading: true).isEmpty, isTrue);
      expect(const SearchState(error: 'boom').isEmpty, isTrue);
    });
  });

  group('SearchState.topResult', () {
    test('null when everything empty', () {
      expect(const SearchState().topResult, isNull);
    });

    test('priority is song > album > artist > playlist', () {
      final full = SearchState(
        songs: [song('v1')],
        albums: [album],
        artists: [artist],
        playlists: [playlist],
      );
      expect(full.topResult!.type, SearchEntityType.song);

      final noSong = SearchState(
        albums: [album],
        artists: [artist],
        playlists: [playlist],
      );
      expect(noSong.topResult!.type, SearchEntityType.album);

      const noSongAlbum = SearchState(
        artists: [artist],
        playlists: [playlist],
      );
      expect(noSongAlbum.topResult!.type, SearchEntityType.artist);

      const onlyPlaylist = SearchState(playlists: [playlist]);
      expect(onlyPlaylist.topResult!.type, SearchEntityType.playlist);
      expect((onlyPlaylist.topResult!.item as PlaylistSearchResult).name, 'Mix');
    });

    test('top song item is the first song', () {
      final s = SearchState(songs: [song('v1'), song('v2')]);
      expect((s.topResult!.item as SearchResult).videoId, 'v1');
    });
  });

  group('SearchState.copyWith correctedFrom', () {
    test('correction banner survives list updates when re-passed', () {
      const corrected = SearchState(query: 'fixed', correctedFrom: 'orignal');
      final next = corrected.copyWith(
        correctedFrom: corrected.correctedFrom,
        songs: [song('v1')],
      );
      expect(next.correctedFrom, 'orignal');
      expect(next.songs, hasLength(1));
    });

    test('new query without correctedFrom clears the banner', () {
      const corrected = SearchState(query: 'fixed', correctedFrom: 'orignal');
      final next = corrected.copyWith(query: 'something else');
      expect(next.correctedFrom, isNull);
      expect(next.query, 'something else');
    });

    test('scalar fields keep values when untouched', () {
      const s = SearchState(query: 'q', isLoading: true, error: 'e');
      final next = s.copyWith(songs: [song('v1')]);
      expect(next.query, 'q');
      expect(next.isLoading, isTrue);
      // copyWith takes error as pass-through (null clears) — pin it.
      expect(next.error, isNull);
    });
  });
}
