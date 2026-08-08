/// Multi-entity search architecture (Phase 6.5B — Global Search).
///
/// ⚠️ [SearchResult] (playback_engine.dart) is left untouched — it stays
/// the song-search shape the whole playback layer already depends on.
/// This file adds the OTHER three entity shapes so SearchController can
/// return all four categories without changing SearchResult's contract.
library;

/// Which content type a search result represents — used by the UI to
/// pick the right section/icon, and by navigation to pick the right
/// route (song → /song/:id, album → /album/:id, artist → /artist/:id,
/// playlist → /playlist/:id).
enum SearchEntityType { song, album, artist, playlist }

/// An album derived from grouping Songs rows by (albumId, albumName) —
/// NOT backed by a dedicated Albums table yet (see LibraryRepository.
/// searchAlbums() doc-comment). [artworkUrl] comes from ArtworkResolver
/// (first matching song's thumbnail), never invented.
class AlbumSearchResult {
  final String albumId;
  final String albumName;
  final String? artworkUrl;
  final String? artistName;

  const AlbumSearchResult({
    required this.albumId,
    required this.albumName,
    this.artworkUrl,
    this.artistName,
  });
}

/// An artist derived from grouping Songs rows by artistId — NOT backed
/// by a dedicated Artists table yet (see LibraryRepository.
/// searchArtists() doc-comment). [artworkUrl] comes from ArtworkResolver
/// (first matching song's thumbnail), never invented.
class ArtistSearchResult {
  final String artistId;
  final String artistName;
  final String? artworkUrl;

  const ArtistSearchResult({
    required this.artistId,
    required this.artistName,
    this.artworkUrl,
  });
}

/// A user playlist matching the search query by name — thin projection
/// of PlaylistSummary (playlist_model.dart), kept separate so this file
/// doesn't need to import playlist internals beyond what search needs.
class PlaylistSearchResult {
  final String playlistId;
  final String name;
  final int itemCount;
  final String? coverThumbnail;

  const PlaylistSearchResult({
    required this.playlistId,
    required this.name,
    required this.itemCount,
    this.coverThumbnail,
  });
}