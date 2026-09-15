import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/sync_manager.dart';
import '../data/sync/conflict_resolver.dart';
import '../data/sync/retry_manager.dart';
import '../data/repositories/sync_repository.dart';
import 'database_provider.dart';

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return SyncRepository();
});

final conflictResolverProvider = Provider<ConflictResolver>((ref) {
  return const ConflictResolver();
});

final retryManagerProvider = Provider<RetryManager>((ref) {
  return RetryManager();
});

final syncManagerProvider = Provider<SyncManager>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final repo = ref.watch(syncRepositoryProvider);
  final conflict = ref.watch(conflictResolverProvider);
  final retry = ref.watch(retryManagerProvider);

  final manager = SyncManager(
    db: db,
    syncRepo: repo,
    conflictResolver: conflict,
    retryManager: retry,
  );

  // Auto-start periodic sync
  manager.startPeriodicSync(interval: const Duration(seconds: 30));

  ref.onDispose(() {
    manager.stopPeriodicSync();
  });

  return manager;
});
