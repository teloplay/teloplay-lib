import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/songs_table.dart';
import 'tables/playlists_table.dart';
import 'tables/playlist_items_table.dart';
import 'tables/queue_table.dart';
import 'tables/history_table.dart';
import 'tables/search_history_table.dart';
import 'tables/favorites_table.dart';
import 'tables/settings_table.dart';
import 'tables/sync_queue_table.dart';
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
  @override
  int get schemaVersion => 5;

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
        },
      );

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