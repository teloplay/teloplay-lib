import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/data/drift/database.dart';
import 'package:teloplay/providers/database_provider.dart';
import 'package:teloplay/providers/search_provider.dart';
import 'package:teloplay/services/cache/metadata_cache_service.dart';
import 'package:teloplay/services/metadata/deezer_client.dart';

/// Batch C — local-library category See-All (albums/artists/playlists).
/// Full filtered set from existing repo methods, sliced in memory; no
/// catalog API. Headless-safe: album/artist paths touch only Drift
/// (playlist path is user-scoped → auth-gated, documented below).
void main() {
  Future<ProviderContainer> containerWithSongs() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.batch((b) {
      b.insertAll(db.songs, [
        SongsCompanion.insert(
          id: 'v1',
          title: 'Alpha Song',
          author: 'Alpha Band',
          thumbnail: 'http://t/1.jpg',
          albumId: const Value('al1'),
          albumName: const Value('Alpha Album'),
          artistId: const Value('ar1'),
        ),
        SongsCompanion.insert(
          id: 'v2',
          title: 'Alpha Reprise',
          author: 'Alpha Band',
          thumbnail: 'http://t/2.jpg',
          albumId: const Value('al1'),
          albumName: const Value('Alpha Album'),
          artistId: const Value('ar1'),
        ),
        SongsCompanion.insert(
          id: 'v3',
          title: 'Beta Tune',
          author: 'Beta Act',
          thumbnail: 'http://t/3.jpg',
          albumId: const Value('al2'),
          albumName: const Value('Beta Album'),
          artistId: const Value('ar2'),
        ),
      ]);
    });
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // DeezerClient's production provider reads EnvConfig (DotEnv),
        // uninitialized headless — inject the client directly with the
        // same memory DB. Category branches under test never touch it.
        deezerClientProvider.overrideWith(
          (ref) => DeezerClient(cache: MetadataCacheService(db: db)),
        ),
      ],
    );
    addTearDown(() {
      c.dispose();
      db.close();
    });
    return c;
  }

  group('searchCategoryAlbums', () {
    test('returns full filtered set with identity', () async {
      final c = await containerWithSongs();
      final albums = await c
          .read(searchOrchestratorProvider)
          .searchCategoryAlbums('alpha');

      expect(albums, hasLength(1));
      expect(albums.first.albumId, 'al1');
      expect(albums.first.albumName, 'Alpha Album');
    });

    test('in-memory slicing honors page/pageSize', () async {
      final c = await containerWithSongs();
      final orch = c.read(searchOrchestratorProvider);

      // 'a' matches both albums ('Alpha Album', 'Beta Album').
      final p0 =
          await orch.searchCategoryAlbums('a', page: 0, pageSize: 1);
      final p1 =
          await orch.searchCategoryAlbums('a', page: 1, pageSize: 1);
      final p2 =
          await orch.searchCategoryAlbums('a', page: 2, pageSize: 1);

      expect(p0, hasLength(1));
      expect(p1, hasLength(1));
      expect(p0.first.albumId, isNot(p1.first.albumId));
      expect(p2, isEmpty);
    });

    test('no match and blank query yield empty', () async {
      final c = await containerWithSongs();
      final orch = c.read(searchOrchestratorProvider);

      expect(await orch.searchCategoryAlbums('zzz'), isEmpty);
      expect(await orch.searchCategoryAlbums('   '), isEmpty);
    });
  });

  group('searchCategoryArtists', () {
    test('returns full filtered set with identity', () async {
      final c = await containerWithSongs();
      final artists = await c
          .read(searchOrchestratorProvider)
          .searchCategoryArtists('beta');

      expect(artists, hasLength(1));
      expect(artists.first.artistId, 'ar2');
      expect(artists.first.artistName, 'Beta Act');
    });

    test('in-memory slicing honors page/pageSize', () async {
      final c = await containerWithSongs();
      final orch = c.read(searchOrchestratorProvider);

      final p0 =
          await orch.searchCategoryArtists('a', page: 0, pageSize: 1);
      final p1 =
          await orch.searchCategoryArtists('a', page: 1, pageSize: 1);
      final p2 =
          await orch.searchCategoryArtists('a', page: 2, pageSize: 1);

      expect(p0, hasLength(1));
      expect(p1, hasLength(1));
      expect(p0.first.artistId, isNot(p1.first.artistId));
      expect(p2, isEmpty);
    });

    test('blank query yields empty', () async {
      final c = await containerWithSongs();
      expect(
        await c
            .read(searchOrchestratorProvider)
            .searchCategoryArtists('  '),
        isEmpty,
      );
    });
  });

  group('searchCategoryPlaylists', () {
    test('blank query yields empty without touching auth', () async {
      final c = await containerWithSongs();
      expect(
        await c
            .read(searchOrchestratorProvider)
            .searchCategoryPlaylists('  '),
        isEmpty,
      );
    });

    test('user-scoped query degrades to empty headless (no session)', () async {
      // Playlist search filters by Supabase uid, which does not exist
      // headless — the catchError path yields []. Positive-path coverage
      // needs a signed-in session (manual QA); query semantics are the
      // same LIKE filter as the already-covered preview fan-out.
      final c = await containerWithSongs();
      expect(
        await c
            .read(searchOrchestratorProvider)
            .searchCategoryPlaylists('anything'),
        isEmpty,
      );
    });
  });
}
