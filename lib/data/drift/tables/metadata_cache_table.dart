import 'package:drift/drift.dart';

/// Metadata cache (L2) — Deezer/Last.fm/MusicBrainz/YouTube response cache.
/// এটা audio byte cache (LRU/MediaAssetManager) থেকে সম্পূর্ণ আলাদা —
/// শুধু text/JSON metadata। TTL 30 days, rebuildable, sync অপ্রয়োজনীয়।
class MetadataCache extends Table {
  /// 'deezer' | 'lastfm' | 'musicbrainz' | 'youtube'
  TextColumn get source => text()();

  /// 'track' | 'artist' | 'album' | 'search'
  TextColumn get type => text()();

  /// External API ID (Deezer track id, MBID, etc.)
  TextColumn get id => text()();

  /// JSON blob of the cached response
  TextColumn get data => text()();

  DateTimeColumn get cachedAt =>
      dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {source, type, id};
}
