import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../drift/database.dart';
import 'base_repository.dart';

/// ⚠️ Phase 3 (Smart Cache) — `Songs` টেবিলের cache-metadata column
/// (`cachedLocally`, `cachePath`, `cacheSizeBytes` — Phase 0.9-এই যোগ
/// করা হয়েছিল, নতুন migration লাগেনি) manage করে।
///
/// এই repository ইচ্ছাকৃতভাবে filesystem টাচ করে না (সেটা
/// `MediaAssetManager`-এর দায়িত্ব, `lib/data/cache/`-এ) — শুধু DB
/// bookkeeping। `CacheService` দুটোকে orchestrate করে: filesystem
/// write সফল হলে এই repository দিয়ে DB row আপডেট করে, filesystem
/// evict হলে এই repository দিয়ে DB row clear করে।
///
/// Audio-only — `Songs` টেবিলে শুধু audio cache metadata আছে (roadmap-
/// এর Phase 0.9 সিদ্ধান্ত অনুযায়ী)। Thumbnail cache-এর DB-side
/// bookkeeping দরকার নেই — thumbnail cache শুধু filesystem lookup
/// (`MediaAssetManager.get()`-এর file-exists check) দিয়েই যথেষ্ট,
/// কারণ `CachedArtwork` widget প্রতিবার videoId দিয়ে lookup করবে, আলাদা
/// কোনো "cachedLocally" flag persist করার দরকার নেই (unlike audio,
/// যেখানে playback-time সিদ্ধান্ত — download করব নাকি stream করব —
/// এর জন্য দ্রুত DB flag check করা useful, filesystem stat call এড়াতে)।
class CacheRepository extends BaseRepository {
  CacheRepository(super.db);

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  /// একটা track সফলভাবে cache হলে `Songs` row আপডেট করা। Row না থাকলে
  /// (এই videoId কখনো favorites/history/queue-তে touch হয়নি) কিছুই
  /// করা হয় না — cache metadata শুধু বিদ্যমান `Songs` row-এই বসে, নতুন
  /// row insert করা এই repository-র দায়িত্ব না (`Songs` FK integrity —
  /// queue/history/favorites যেভাবে insert করে সেভাবেই হওয়া উচিত)।
  Future<void> markCached({
    required String videoId,
    required String cachePath,
    required int cacheSizeBytes,
  }) async {
    try {
      final rowsAffected = await (db.update(db.songs)
            ..where((t) => t.id.equals(videoId)))
          .write(
        SongsCompanion(
          cachedLocally: const Value(true),
          cachePath: Value(cachePath),
          cacheSizeBytes: Value(cacheSizeBytes),
          cacheChecksum: const Value(null), // নতুন cache — পুরনো checksum invalid
        ),
      );

      if (rowsAffected == 0) {
        AppLogger.performance(
          '[cache-repo] markCached: কোনো matching Songs row নেই '
          '(videoId=$videoId) — filesystem cache থাকলেও DB flag সেট '
          'হলো না, পরের bootstrap-এ orphan হিসেবে detect হতে পারে',
        );
        return;
      }

      AppLogger.performance('[cache-repo] markCached: videoId=$videoId');
    } catch (e) {
      AppLogger.error('CacheRepository.markCached failed (videoId=$videoId)', e);
    }
  }

  /// Eviction-এর পরে `Songs` row-এর cache flag clear করা (row নিজে
  /// delete হয় না — গানটা এখনো favorites/history/queue-তে থাকতে পারে,
  /// শুধু আর locally cached না)।
  Future<void> clearCacheFlag(String videoId) async {
    try {
      await (db.update(db.songs)..where((t) => t.id.equals(videoId))).write(
        const SongsCompanion(
          cachedLocally: Value(false),
          cachePath: Value(null),
          cacheSizeBytes: Value(null),
          cacheChecksum: Value(null),
        ),
      );
      AppLogger.performance('[cache-repo] clearCacheFlag: videoId=$videoId');
    } catch (e) {
      AppLogger.error(
        'CacheRepository.clearCacheFlag failed (videoId=$videoId)',
        e,
      );
    }
  }

  /// App-startup warm-up-এর জন্য — বর্তমানে `cachedLocally=true` মার্ক
  /// করা সব track ফেরত দেয় (videoId + cachePath + cacheSizeBytes +
  /// cacheChecksum), যাতে `CacheService` filesystem-এর সাথে DB reconcile
  /// করতে পারে এবং Item D verify methods checksum ব্যবহার করতে পারে।
  Future<List<({String videoId, String cachePath, int sizeBytes, String? cacheChecksum})>>
      getAllCachedSongs() async {
    try {
      final rows = await (db.select(db.songs)
            ..where((t) => t.cachedLocally.equals(true)))
          .get();

      return rows
          .where((r) => r.cachePath != null && r.cacheSizeBytes != null)
          .map((r) => (
                videoId: r.id,
                cachePath: r.cachePath!,
                sizeBytes: r.cacheSizeBytes!,
                cacheChecksum: r.cacheChecksum,
              ))
          .toList();
    } catch (e) {
      AppLogger.error('CacheRepository.getAllCachedSongs failed', e);
      return [];
    }
  }

  /// ⚠️ Frequently Played priority cache — RESERVED, Phase 3-এ কার্যকর
  /// না (দেখো roadmap decision: "cache priority abstraction এখনই,
  /// frequently_played tier future BehaviourTracking integration-এর
  /// জন্য reserved")।
  ///
  /// এই মেথড এখন placeholder — signature/contract ঠিক করে রাখা হলো
  /// যাতে `CacheService`-এর priority-abstraction layer আজই এটার against
  /// কল করতে পারে (no-op হিসেবে, খালি list রিটার্ন করে), পরে
  /// `HistoryEntries`-এর উপর play-count aggregation query বসালেই এই
  /// একটা মেথড ভরাট করলেই চলবে — caller-side (`CacheService`) কোনো
  /// change লাগবে না।
  ///
  /// Non-throwing, non-blocking — এখন সবসময় empty list।
  Future<List<String>> getFrequentlyPlayedVideoIds({int limit = 10}) async {
    // TODO(Phase 7+ bring-forward candidate): HistoryEntries থেকে
    // videoId GROUP BY করে play-count/completion-rate অনুযায়ী ORDER BY
    // করে top-N ফেরত দেওয়া। এখন `BehaviourTrackingService`-এর data
    // যথেষ্ট সমৃদ্ধ থাকলেও (completed/skipped capture হচ্ছে Phase 1
    // থেকেই), এই query implement করা এখন Phase 3-এর committed core
    // scope (current+preload+LRU) না বলে ইচ্ছাকৃতভাবে বাদ রাখা হলো।
    return const [];
  }

  /// ✅ Phase 3 Item D — SHA-256 checksum persist করা (lazy-populate বা
  /// re-verify-এর পরে আপডেট)। Row না থাকলে/videoId না মিললে silently
  /// skip (markCached()-এর মতোই pattern)।
  Future<void> setChecksum(String videoId, String checksum) async {
    try {
      final rowsAffected = await (db.update(db.songs)
            ..where((t) => t.id.equals(videoId)))
          .write(
        SongsCompanion(
          cacheChecksum: Value(checksum),
        ),
      );

      if (rowsAffected == 0) {
        AppLogger.performance(
          '[cache-repo] setChecksum: কোনো matching Songs row নেই '
          '(videoId=$videoId)',
        );
      }
    } catch (e) {
      AppLogger.error('CacheRepository.setChecksum failed (videoId=$videoId)', e);
    }
  }

  /// ✅ Phase 3 Item D — একটা নির্দিষ্ট cached track-এর তথ্য একক lookup
  /// (verifySingleTrack()-এর জন্য, পুরো list না এনে)।
  Future<({String videoId, String cachePath, int sizeBytes, String? cacheChecksum})?>
      getCachedSong(String videoId) async {
    try {
      final row = await (db.select(db.songs)
            ..where((t) => t.id.equals(videoId) & t.cachedLocally.equals(true)))
          .getSingleOrNull();

      if (row == null || row.cachePath == null || row.cacheSizeBytes == null) {
        return null;
      }

      return (
        videoId: row.id,
        cachePath: row.cachePath!,
        sizeBytes: row.cacheSizeBytes!,
        cacheChecksum: row.cacheChecksum,
      );
    } catch (e) {
      AppLogger.error('CacheRepository.getCachedSong failed (videoId=$videoId)', e);
      return null;
    }
  }

  /// ✅ Phase 3 Item D — orphan-file scan (scanForOrphanFiles())-এর জন্য,
  /// দ্রুত membership-check হিসেবে Set ফেরত দেয় (videoId-only, বাকি
  /// metadata দরকার নেই এখানে)।
  Future<Set<String>> getCachedVideoIdSet() async {
    try {
      final rows = await (db.select(db.songs)
            ..where((t) => t.cachedLocally.equals(true)))
          .get();
      return rows.map((r) => r.id).toSet();
    } catch (e) {
      AppLogger.error('CacheRepository.getCachedVideoIdSet failed', e);
      return {};
    }
  }
}