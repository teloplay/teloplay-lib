import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/logging/app_logger.dart';
import '../data/drift/database.dart';
import '../data/sync/sync_manager.dart';

/// Phase 4 — Core Sync Service integrating Drift Offline Queue with Supabase Cloud Sync.
class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();
  SyncService._();

  SyncManager? _syncManager;

  void initialize(AppDatabase db) {
    _syncManager = SyncManager(db: db);
    _syncManager!.startPeriodicSync(interval: const Duration(seconds: 30));

    // Listen to Supabase auth state change to trigger sync upon login
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        AppLogger.sync('Auth state changed to authenticated -> trigger syncPendingQueue');
        unawaited(_syncManager?.syncPendingQueue());
      }
    });

    AppLogger.sync('SyncService initialized with 30s background timer and auth triggers');
  }

  /// Manually triggers a queue flush to Supabase.
  Future<void> syncPendingQueue() async {
    if (_syncManager == null) {
      debugPrint('[Sync] SyncService not initialized');
      return;
    }
    await _syncManager!.syncPendingQueue();
  }

  void dispose() {
    _syncManager?.stopPeriodicSync();
    _syncManager = null;
  }
}