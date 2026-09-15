import '../../core/logging/app_logger.dart';

/// Phase 4 — Conflict Resolver for Sync Engine (Last-Write-Wins based on updatedAt).
class ConflictResolver {
  const ConflictResolver();

  /// Compares local and remote timestamps to resolve conflicts.
  /// Returns `true` if local record should win and overwrite remote.
  bool shouldLocalWin({
    required DateTime localUpdatedAt,
    required DateTime remoteUpdatedAt,
  }) {
    final localWins = localUpdatedAt.isAfter(remoteUpdatedAt);
    AppLogger.sync(
      'Conflict resolved: local($localUpdatedAt) vs remote($remoteUpdatedAt) -> localWins=$localWins',
    );
    return localWins;
  }

  /// Merges two queue arrays or lists deduplicating by ID preserving newest changes.
  List<T> mergeLists<T>({
    required List<T> localList,
    required List<T> remoteList,
    required String Function(T) idExtractor,
  }) {
    final map = <String, T>{};
    for (final item in remoteList) {
      map[idExtractor(item)] = item;
    }
    // Local list overrides remote on duplicate
    for (final item in localList) {
      map[idExtractor(item)] = item;
    }
    return map.values.toList();
  }
}
