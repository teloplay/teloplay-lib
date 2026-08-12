import '../../data/drift/database.dart';
import '../../core/logging/app_logger.dart';

/// L2 metadata cache service — text/JSON only, separate from audio byte cache.
/// TTL: 30 days default. Rebuildable, no sync needed.
class MetadataCacheService {
  final AppDatabase _db;

  MetadataCacheService({required AppDatabase db}) : _db = db;

  /// Get cached metadata if not expired.
  Future<Map<String, dynamic>?> get({
    required String source,
    required String type,
    required String id,
  }) async {
    try {
      final entry = await (_db.select(_db.metadataCache)
            ..where((c) => c.source.equals(source))
            ..where((c) => c.type.equals(type))
            ..where((c) => c.id.equals(id)))
          .getSingleOrNull();

      if (entry == null) return null;

      // Check TTL
      if (DateTime.now().isAfter(entry.expiresAt)) {
        AppLogger.cache('Metadata cache expired: $source/$type/$id');
        await delete(source: source, type: type, id: id);
        return null;
      }

      return entry.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error('Metadata cache get failed: $e');
      return null;
    }
  }

  /// Set metadata with TTL.
  Future<void> set({
    required String source,
    required String type,
    required String id,
    required Map<String, dynamic> data,
    Duration? ttl,
  }) async {
    final expiresAt = DateTime.now().add(ttl ?? const Duration(days: 30));

    await _db.into(_db.metadataCache).insertOnConflictUpdate(
      MetadataCacheCompanion(
        source: Value(source),
        type: Value(type),
        id: Value(id),
        data: Value(data.toString()), // JSON string
        cachedAt: Value(DateTime.now()),
        expiresAt: Value(expiresAt),
      ),
    );

    AppLogger.cache('Metadata cache set: $source/$type/$id (expires: $expiresAt)');
  }

  /// Delete specific entry.
  Future<void> delete({
    required String source,
    required String type,
    required String id,
  }) async {
    await (_db.delete(_db.metadataCache)
          ..where((c) => c.source.equals(source))
          ..where((c) => c.type.equals(type))
          ..where((c) => c.id.equals(id)))
        .go();
  }

  /// Clear all expired entries.
  Future<int> cleanupExpired() async {
    final now = DateTime.now();
    final count = await (_db.delete(_db.metadataCache)
          ..where((c) => c.expiresAt.isSmallerThanValue(now)))
        .go();

    AppLogger.cache('Metadata cache cleanup: $count expired entries removed');
    return count;
  }

  /// Get cache size estimate (entry count).
  Future<int> getEntryCount() async {
    final count = await _db.metadataCache.count().getSingle();
    return count;
  }

  /// Clear all entries for a source.
  Future<int> clearSource(String source) async {
    final count = await (_db.delete(_db.metadataCache)
          ..where((c) => c.source.equals(source)))
        .go();

    AppLogger.cache('Metadata cache cleared for source: $source ($count entries)');
    return count;
  }
}