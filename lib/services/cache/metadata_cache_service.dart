import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../data/drift/database.dart';

/// L2 metadata cache service — text/JSON only, separate from audio byte cache.
/// TTL: 30 days default. Rebuildable, no sync needed.
///
/// ⚠️ Fix (Phase 0 v11 stabilization):
/// - `data` column is TEXT (drift `text()`), not a Map — every read/write
///   now goes through `jsonEncode`/`jsonDecode` explicitly. The original
///   version did `data.toString()` on write (Dart's Map.toString() is NOT
///   valid JSON, e.g. `{key: value}` not `{"key":"value"}`) and
///   `entry.data as Map<String, dynamic>` on read (a String can never be
///   cast to a Map — this would have thrown at runtime on every hit).
/// - `getEntryCount()` used `_db.metadataCache.count()`, a method that
///   doesn't exist on a Drift table getter. Rewritten using the same
///   `column.count()` + `addColumns` pattern already used in
///   playlist_repository.dart elsewhere in this codebase.
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

      try {
        return jsonDecode(entry.data) as Map<String, dynamic>;
      } catch (e) {
        // Corrupt/unparseable entry — treat as a miss rather than crash
        // the caller, and clean it up so it doesn't keep failing.
        AppLogger.error('Metadata cache corrupt entry, dropping: $source/$type/$id', e);
        await delete(source: source, type: type, id: id);
        return null;
      }
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
            data: Value(jsonEncode(data)),
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
    final query = _db.selectOnly(_db.metadataCache)
      ..addColumns([_db.metadataCache.id.count()]);
    final row = await query.getSingle();
    return row.read(_db.metadataCache.id.count()) ?? 0;
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
