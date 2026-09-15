import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../drift/database.dart';
import '../repositories/sync_repository.dart';
import 'conflict_resolver.dart';
import 'retry_manager.dart';

/// Phase 4 — Offline-first SyncManager orchestrating Drift queue to Supabase.
class SyncManager {
  final AppDatabase _db;
  final SyncRepository _syncRepo;
  final ConflictResolver conflictResolver;
  final RetryManager _retryManager;

  Timer? _periodicSyncTimer;
  bool _isSyncing = false;

  SyncManager({
    required AppDatabase db,
    SyncRepository? syncRepo,
    ConflictResolver? conflictResolver,
    RetryManager? retryManager,
  })  : _db = db,
        _syncRepo = syncRepo ?? SyncRepository(),
        conflictResolver = conflictResolver ?? const ConflictResolver(),
        _retryManager = retryManager ?? RetryManager();

  void startPeriodicSync({Duration interval = const Duration(seconds: 30)}) {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(interval, (_) => syncPendingQueue());
    AppLogger.sync('SyncManager: Periodic sync started (every ${interval.inSeconds}s)');
  }

  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    AppLogger.sync('SyncManager: Periodic sync stopped');
  }

  /// Drains and synchronizes pending queue items from Drift to Supabase.
  Future<void> syncPendingQueue() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      AppLogger.sync('SyncManager: No logged in user, skipping queue sync');
      return;
    }

    if (_isSyncing) {
      AppLogger.sync('SyncManager: Sync already in progress, skipping tick');
      return;
    }

    _isSyncing = true;

    try {
      final items = await (_db.select(_db.syncQueueItems)
            ..where((t) => t.userId.equals(uid) & t.status.equals('pending'))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(25))
          .get();

      if (items.isEmpty) {
        _isSyncing = false;
        return;
      }

      AppLogger.sync('SyncManager: Processing ${items.length} pending items for user=$uid');

      for (final item in items) {
        await _processItem(item);
      }
    } catch (e) {
      AppLogger.error('SyncManager: Error while draining sync queue', e);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _processItem(SyncQueueItem item) async {
    // Mark as syncing
    await (_db.update(_db.syncQueueItems)..where((t) => t.id.equals(item.id)))
        .write(const SyncQueueItemsCompanion(status: Value('syncing')));

    try {
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;

      switch (item.entityType) {
        case 'favorite':
          if (item.action == 'create') {
            await _syncRepo.upsertFavorite(
              songId: payload['songId'] ?? item.entityId.split(':').last,
              title: payload['title'] ?? 'Unknown',
              author: payload['author'] ?? 'Unknown',
              thumbnail: payload['thumbnail'] ?? '',
              durationSeconds: payload['durationSeconds'],
            );
          } else if (item.action == 'delete') {
            final songId = payload['songId'] ?? item.entityId.split(':').last;
            await _syncRepo.deleteFavorite(songId);
          }
          break;

        case 'queue':
          final queueList = (payload['queue'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          await _syncRepo.syncQueueState(
            queueJson: queueList,
            currentIndex: payload['currentIndex'] ?? 0,
            lastPositionMs: payload['lastPositionMs'] ?? 0,
            currentSongId: payload['currentSongId'],
          );
          break;

        case 'settings':
          await _syncRepo.syncSettings(payload);
          break;

        case 'behaviour_summary':
          await _syncRepo.syncBehaviourSummary(
            topArtists: (payload['topArtists'] as List?)?.cast<Map<String, dynamic>>() ?? [],
            totalPlays: payload['totalPlays'] ?? 0,
            totalSkips: payload['totalSkips'] ?? 0,
            totalCompleted: payload['totalCompleted'] ?? 0,
            totalListenMs: payload['totalListenMs'] ?? 0,
          );
          break;

        default:
          AppLogger.sync('SyncManager: Unknown entityType "${item.entityType}", skipping');
          break;
      }

      // Successful sync: remove from local queue
      await (_db.delete(_db.syncQueueItems)..where((t) => t.id.equals(item.id))).go();
      AppLogger.sync('SyncManager: Item ${item.id} synced and deleted from queue');
    } catch (e) {
      final newRetryCount = item.retryCount + 1;
      final isExceeded = _retryManager.isMaxRetriesExceeded(newRetryCount);

      AppLogger.sync('SyncManager: Failed item ${item.id} (attempt $newRetryCount): $e');

      await (_db.update(_db.syncQueueItems)..where((t) => t.id.equals(item.id))).write(
        SyncQueueItemsCompanion(
          status: Value(isExceeded ? 'failed' : 'pending'),
          retryCount: Value(newRetryCount),
          lastError: Value(e.toString()),
        ),
      );
    }
  }
}
