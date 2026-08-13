import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import 'tables/songs_table.dart';
import 'tables/playlists_table.dart';
import 'tables/playlist_items_table.dart';
import 'tables/queue_table.dart';
import 'tables/history_table.dart';
import 'tables/search_history_table.dart';
import 'tables/favorites_table.dart';
import 'tables/settings_table.dart';
import 'tables/sync_queue_table.dart';
import 'tables/metadata_cache_table.dart';
part 'database.g.dart';

@DriftDatabase(
  tables: [
    Songs,
    Playlists,
    PlaylistItems,
    QueueItems,
    HistoryEntries,
    SearchHistoryEntries, // ⚠️ Phase 0.9 — নতুন, Smart Search foundation
    Favorites,
    SettingsEntries,
    SyncQueueItems,
    MetadataCache, // ⚠️ v11 — Metadata/Discovery/Sync Architecture (L2 cache)
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Testing/mocking-এর জন্য custom executor দিয়ে বানানো যাবে
  AppDatabase.forTesting(super.executor);

  // ⚠️ Phase 0.9 (Foundation Hardening) — schemaVersion 1 → 2 → 3।
  //
  // দুইবার সমস্যা হয়েছিল:
  // 1. dev DB আগেই তৈরি ছিল (v1), তাই schemaVersion 2-এ প্রথমবার বাম্প
  //    করেও `onCreate` rerun হয়নি — `onUpgrade` লাগত (এটা ঠিক করা
  //    হয়েছিল)।
  // 2. প্রথম `onUpgrade` migration-এ ভুলবশত শুধু QueueItems আর
  //    SearchHistoryEntries handle করা হয়েছিল, Songs-এর ৩টা কলাম আর
  //    HistoryEntries.skipped বাদ পড়ে গিয়েছিল। DB একবার schemaVersion=2
  //    হিসেবে persist হয়ে যাওয়ার পর, সেই version number-এ আর কোনো নতুন
  //    বাম্প না করে সংশোধিত migration চালানো সম্ভব ছিল না — Drift internal
  //    metadata-তে "already at version 2" থাকায় `onUpgrade` স্কিপ করে
  //    দিচ্ছিল, ফলে বাকি column গুলো কখনো যোগ হয়নি।
  //
  // তাই schemaVersion আবার বাম্প করে 3 করা হলো, `onUpgrade`-এ `from < 3`
  // চেক দিয়ে বাকি সব বদল (Songs কলাম + HistoryEntries.skipped) সহ পূর্ণ
  // migration চালানো হচ্ছে (idempotent — ইতিমধ্যে-যোগ-হওয়া কলামগুলোর
  // জন্য try/catch দিয়ে নিরাপদে skip করা হচ্ছে, যাতে আংশিক-migrated
  // dev DB-তেও safely rerun করা যায়)।
  //
  // ⚠️ Phase 3 Item D (Cache Health/Diagnostics) — schemaVersion 3 → 4।
  // নতুন Songs.cacheChecksum (nullable TextColumn, SHA-256 verification-এর
  // জন্য) যোগ হলো, একই idempotent `_safeAddColumn` pattern ব্যবহার করে।
  //
  // ⚠️ Phase 6.5B (Album/Artist navigation foundation) — schemaVersion
  // 4 → 5। নতুন Songs.albumId + Songs.albumName (দুটোই nullable
  // TextColumn), একই idempotent `_safeAddColumn` pattern ব্যবহার করে।
  //
  // ⚠️ v11 Fix-First #2 (Sync Queue user-scoping) — schemaVersion 5 → 6।
  // SyncQueueItems.userId (non-nullable TextColumn) যোগ হলো। Existing
  // sync queue entries cross-user leak প্রতিরোধে current logged-in
  // user দিয়ে backfill করা হয় — user null থাকলে (guest/logged-out
  // অবস্থায় পুরনো row) সেই entry গুলো নিরাপদে drop করা হয়, কারণ
  // owner অজানা row sync করা নিজেই leak risk।
  //
  // ⚠️ v11 Metadata/Discovery/Sync Architecture — schemaVersion 6 → 7।
  // নতুন MetadataCache টেবিল (Deezer/Last.fm/MusicBrainz/YouTube L2
  // metadata cache, audio byte cache থেকে সম্পূর্ণ আলাদা)।
  //
  // ⚠️ v11 Continue Session (Section H) — no schema change needed.
  // QueueRepository (queue_table.dart: userId/songId/position/isCurrent/
  // lastPositionMs) already persists the full queue + current position —
  // exactly what "multi-song resume" needs. A separate ContinueSessions
  // table would have duplicated that data; ContinueSessionManager builds
  // on QueueRepository instead (see services/session/continue_session_manager.dart).
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 3) {
            // প্রতিটা column/table আলাদা try/catch-এ — কারণ dev DB-তে
            // ইতিমধ্যে কিছু column (যেমন queueItems.lastPositionMs,
            // searchHistoryEntries) আগের partial migration থেকে যোগ
            // হয়ে থাকতে পারে। "duplicate column"/"table already exists"
            // ধরনের error নিরাপদে ignore করা হচ্ছে, বাকিগুলো ঠিকভাবে যোগ
            // হবে।
            await _safeAddColumn(m, songs, songs.genre);
            await _safeAddColumn(m, songs, songs.artistId);
            await _safeAddColumn(m, songs, songs.platformSource);
            await _safeAddColumn(m, queueItems, queueItems.lastPositionMs);
            await _safeAddColumn(m, historyEntries, historyEntries.skipped);
            await _safeCreateTable(m, searchHistoryEntries);
          }
          if (from < 4) {
            // Phase 3 Item D — Cache Health/Diagnostics.
            await _safeAddColumn(m, songs, songs.cacheChecksum);
          }
          if (from < 5) {
            // Phase 6.5B — Album/Artist navigation foundation.
            await _safeAddColumn(m, songs, songs.albumId);
            await _safeAddColumn(m, songs, songs.albumName);
          }
          if (from < 6) {
            // v11 Fix-First #2 — Sync Queue user-scoping.
            //
            // SyncQueueItems.userId is declared NOT NULL (no default) in
            // the table class — correct for fresh installs (onCreate), but
            // SQLite's `ALTER TABLE ADD COLUMN NOT NULL` fails on a table
            // that already has rows unless a default is supplied at
            // ADD-COLUMN time. So the raw SQL below adds it as TEXT NOT
            // NULL DEFAULT '' (matching the generated column's storage
            // type), then _backfillOrDropOrphanSyncQueueItems() replaces
            // that placeholder with a real userId or deletes the orphan
            // row — no row is ever left with the '' placeholder.
            try {
              await customStatement(
                "ALTER TABLE sync_queue_items ADD COLUMN user_id TEXT NOT NULL DEFAULT ''",
              );
            } catch (_) {
              // column already exists — safe to ignore (idempotent, same
              // pattern as _safeAddColumn).
            }
            await _backfillOrDropOrphanSyncQueueItems();
          }
          if (from < 7) {
            // v11 Metadata/Discovery/Sync Architecture — L2 metadata cache.
            await _safeCreateTable(m, metadataCache);
          }
        },
      );

  /// [userId] non-nullable column যোগ করার পর, migration-এর আগে থেকে থাকা
  /// row গুলোর owner অজানা (column-টাই ছিল না তখন)। Current logged-in
  /// user থাকলে সেই user-এর ধরে backfill করা হয় (একক-user dev/production
  /// অবস্থায় এটাই সঠিক ধারণা); logged-in user না থাকলে (guest/logged-out
  /// অবস্থায় upgrade হচ্ছে) owner অজানা row গুলো নিরাপদে delete করা হয় —
  /// অজানা owner-এর row sync-queue-তে রেখে দেওয়া নিজেই cross-user leak
  /// risk, খালি queue থেকে শুরু করা নিরাপদ (sync queue rebuildable —
  /// পরের write operation-এই আবার entry তৈরি হবে)।
  Future<void> _backfillOrDropOrphanSyncQueueItems() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null) {
        await customStatement(
          "UPDATE sync_queue_items SET user_id = ? WHERE user_id IS NULL OR user_id = ''",
          [currentUserId],
        );
      } else {
        await customStatement(
          "DELETE FROM sync_queue_items WHERE user_id IS NULL OR user_id = ''",
        );
      }
    } catch (e) {
      AppLogger.drift('Sync queue userId backfill skipped: $e');
    }
  }

  Future<void> _safeAddColumn<T extends Object>(
    Migrator m,
    TableInfo table,
    GeneratedColumn<T> column,
  ) async {
    try {
      await m.addColumn(table, column);
    } catch (_) {
      // column আগে থেকেই আছে ধরে নিয়ে নিরাপদে skip — dev-only পরিস্থিতি,
      // production migration-এ এভাবে blanket-ignore করা হবে না।
    }
  }

  Future<void> _safeCreateTable(Migrator m, TableInfo table) async {
    try {
      await m.createTable(table);
    } catch (_) {
      // table আগে থেকেই আছে ধরে নিয়ে নিরাপদে skip।
    }
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'teloplay_db');
}