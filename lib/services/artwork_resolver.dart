import '../data/drift/database.dart';

/// Single, reusable resolver for album/artist artwork — used by Search,
/// Album Page, Artist Page, and Home rails alike, so the fallback
/// strategy lives in exactly one place.
///
/// ⚠️ Current strategy (no dedicated Albums/Artists table yet):
/// - Album artwork  → first Songs row matching this albumId, its thumbnail.
/// - Artist artwork → first Songs row matching this artistId, its thumbnail.
///
/// Future-ready: if a dedicated Albums table, artist profile metadata,
/// an external metadata provider, or a cached-artwork service arrives
/// later, only this class's internals change — every caller (Search UI,
/// AlbumDetailsScreen, ArtistPageScreen, Home rails) keeps working
/// unmodified, since they all go through resolveAlbumArtwork()/
/// resolveArtistArtwork() rather than querying Songs directly.
///
/// Returns null (never a fake/placeholder URL) when no matching Songs
/// row exists — callers show a generic icon/gradient placeholder in
/// that case, consistent with the rest of the app's "never invent data"
/// rule (see SongDetailsScreen/AlbumDetailsScreen doc-comments).
class ArtworkResolver {
  final AppDatabase db;

  const ArtworkResolver(this.db);

  Future<String?> resolveAlbumArtwork(String albumId) async {
    final row = await (db.select(db.songs)
          ..where((t) => t.albumId.equals(albumId))
          ..limit(1))
        .getSingleOrNull();
    return row?.thumbnail;
  }

  Future<String?> resolveArtistArtwork(String artistId) async {
    final row = await (db.select(db.songs)
          ..where((t) => t.artistId.equals(artistId))
          ..limit(1))
        .getSingleOrNull();
    return row?.thumbnail;
  }
}