import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/data/drift/database.dart';
import 'package:teloplay/data/repositories/library_repository.dart';

/// Batch A (A1/A2) — album/artist identity must ride on the detail-query
/// mappings (no Albums table exists; headers and grouping derive from
/// rows). Headless-safe: these two methods touch only `db`, never auth.
void main() {
  Future<AppDatabase> openDb() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  Future<void> seedSongs(AppDatabase db) {
    return db.batch((b) {
      b.insertAll(db.songs, [
        SongsCompanion.insert(
          id: 'v1',
          title: 'Track One',
          author: 'Artist A',
          thumbnail: 'http://t/1.jpg',
          albumId: const Value('al1'),
          albumName: const Value('First Album'),
          artistId: const Value('ar1'),
        ),
        SongsCompanion.insert(
          id: 'v2',
          title: 'Track Two',
          author: 'Artist A',
          thumbnail: 'http://t/2.jpg',
          albumId: const Value('al1'),
          albumName: const Value('First Album'),
          artistId: const Value('ar1'),
        ),
        SongsCompanion.insert(
          id: 'v3',
          title: 'Lone Single',
          author: 'Artist A',
          thumbnail: 'http://t/3.jpg',
          artistId: const Value('ar1'),
        ),
      ]);
    });
  }

  group('getSongsByAlbumId identity carry (A1)', () {
    test('rows carry albumName for the real header', () async {
      final db = await openDb();
      await seedSongs(db);

      final tracks =
          await LibraryRepository(db).getSongsByAlbumId('al1');

      expect(tracks, hasLength(2));
      for (final t in tracks) {
        expect(t.albumId, 'al1');
        expect(t.albumName, 'First Album');
      }
    });

    test('unknown album id yields empty (header shows empty state)',
        () async {
      final db = await openDb();
      await seedSongs(db);

      expect(
        await LibraryRepository(db).getSongsByAlbumId('nope'),
        isEmpty,
      );
    });
  });

  group('getSongsByArtistId identity carry (A2)', () {
    test('rows carry artistId + album identity for sections', () async {
      final db = await openDb();
      await seedSongs(db);

      final tracks =
          await LibraryRepository(db).getSongsByArtistId('ar1');

      expect(tracks, hasLength(3));
      for (final t in tracks) {
        expect(t.artistId, 'ar1');
      }
      final grouped =
          tracks.where((t) => t.albumId == 'al1').toList();
      expect(grouped, hasLength(2));
      expect(
        grouped.every((t) => t.albumName == 'First Album'),
        isTrue,
      );
      // Singles = rows without album identity.
      expect(
        tracks.where((t) => t.albumId == null).map((t) => t.videoId),
        contains('v3'),
      );
    });
  });
}
