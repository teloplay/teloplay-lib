import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../core/playback/playback_engine.dart';
import '../drift/database.dart';
import 'base_repository.dart';
import 'sync_queue_helper.dart';

/// Queue persistence — app restart হলেও in-memory queue হারিয়ে যাবে না।
/// Roadmap-এর নির্দেশ অনুযায়ী এটা Background playback-এর *আগে* আনা
/// হচ্ছে, কারণ background playback চালু হলে app kill হলে queue হারানো
/// একটা সরাসরি regression হতো।
///
/// `queue_items.song_id` টেবিলের FK `songs.id`-কে point করে, তাই কোনো
/// track queue-তে persist করার আগে সংশ্লিষ্ট [Song] row upsert করা লাগে
/// (SearchResult থেকে Song-এ রূপান্তর করে)।
///
/// Multi-user schema মেনে চলা হয়েছে — সব query/write `userId` দিয়ে
/// scoped, Guest mode-ও Anonymous Auth ব্যবহার করে বলে `currentUser`
/// সবসময় থাকা উচিত; না থাকলে সেটা একটা bug (silent wrong-user write
/// এড়াতে exception ছোড়া হয়, নীরবে ignore করা হয় না)।
class QueueRepository extends BaseRepository {
  final SyncQueueHelper _syncQueue;

  QueueRepository(AppDatabase db)
      : _syncQueue = SyncQueueHelper(db),
        super(db);

  String get _userId {
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) {
      throw StateError(
        'QueueRepository: কোনো authenticated user নেই। '
        'Guest mode-ও Anonymous Auth ব্যবহার করে, তাই এটা অপ্রত্যাশিত।',
      );
    }
    return id;
  }

  /// ⚠️ Public করা হয়েছে (আগে `_upsertSong` ছিল) — `MusicPlayerRepository`
  /// এখন `playVideoId()`-এ playback শুরুর সময়েই এই একই upsert চালায়,
  /// queue/favorite touch হওয়ার অপেক্ষা না করে Songs FK integrity-র
  /// একমাত্র entry point এটাই, তাই duplicate না করে reuse করা হচ্ছে।
  Future<void> upsertSong(SearchResult track) async {
    await db.into(db.songs).insertOnConflictUpdate(
          SongsCompanion.insert(
            id: track.videoId,
            title: track.title,
            author: track.author,
            thumbnail: track.thumbnail,
            durationSeconds: track.duration != null
                ? Value(track.duration!.inSeconds)
                : const Value.absent(),
            // ⚠️ Backlog #1 fix — daemon (Main.kt) এখন SongItem থেকে
            // artistId/albumId/albumName পাঠায়। এখানে সরাসরি Songs row-এ
            // upsert করা হচ্ছে যদি track-এ এই তথ্য থাকে (nullable, তাই
            // না থাকলে Value.absent() — বিদ্যমান row-এর পুরনো/অন্য
            // caller থেকে পাওয়া মান accidentally null দিয়ে overwrite
            // করে না)।
            artistId: track.artistId != null
                ? Value(track.artistId!)
                : const Value.absent(),
            albumId: track.albumId != null
                ? Value(track.albumId!)
                : const Value.absent(),
            albumName: track.albumName != null
                ? Value(track.albumName!)
                : const Value.absent(),
          ),
        );
  }

  Future<void> saveQueue(List<SearchResult> queue, int currentIndex) async {
    if (queue.isEmpty) {
      await clearQueue();
      return;
    }

    final userId = _userId;

    await db.transaction(() async {
      for (final track in queue) {
        await upsertSong(track); // _upsertSong থেকে বদলে
      }

      await (db.delete(db.queueItems)
            ..where((t) => t.userId.equals(userId)))
          .go();

      for (var i = 0; i < queue.length; i++) {
        await db.into(db.queueItems).insert(
              QueueItemsCompanion.insert(
                userId: userId,
                songId: queue[i].videoId,
                position: i,
                isCurrent: Value(i == currentIndex),
              ),
            );
      }
    });

    AppLogger.playback(
      'Queue persisted: ${queue.length} tracks, currentIndex=$currentIndex',
    );

    await _syncQueue.enqueue(
      entityType: 'queue',
      entityId: userId,
      action: 'update',
      payload: {'size': queue.length, 'currentIndex': currentIndex},
    );
  }

  Future<({List<SearchResult> queue, int currentIndex})> loadQueue() async {
    final userId = _userId;

    final rows = await (db.select(db.queueItems)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .join([
      innerJoin(db.songs, db.songs.id.equalsExp(db.queueItems.songId)),
    ]).get();

    final queue = <SearchResult>[];
    var currentIndex = -1;

    for (final row in rows) {
      final queueItem = row.readTable(db.queueItems);
      final song = row.readTable(db.songs);

      queue.add(SearchResult(
        videoId: song.id,
        title: song.title,
        author: song.author,
        thumbnail: song.thumbnail,
        duration: song.durationSeconds != null
            ? Duration(seconds: song.durationSeconds!)
            : null,
        artistId: song.artistId,
        albumId: song.albumId,
        albumName: song.albumName,
      ));

      if (queueItem.isCurrent) {
        currentIndex = queue.length - 1;
      }
    }

    AppLogger.playback(
      'Queue restored: ${queue.length} tracks, currentIndex=$currentIndex',
    );

    return (queue: queue, currentIndex: currentIndex);
  }

  Future<void> clearQueue() async {
    final userId = _userId;
    await (db.delete(db.queueItems)..where((t) => t.userId.equals(userId)))
        .go();
    AppLogger.playback('Queue cleared for user');
  }

  Future<void> updateCurrentIndex(int newIndex) async {
    final userId = _userId;
    final now = DateTime.now();

    await db.transaction(() async {
      await (db.update(db.queueItems)
            ..where((t) => t.userId.equals(userId)))
          .write(const QueueItemsCompanion(isCurrent: Value(false)));

      await (db.update(db.queueItems)
            ..where((t) =>
                t.userId.equals(userId) & t.position.equals(newIndex)))
          .write(QueueItemsCompanion(
            isCurrent: const Value(true),
            updatedAt: Value(now),
          ));
    });

    AppLogger.playback(
      'Queue currentIndex updated: newIndex=$newIndex, updatedAt=$now',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ⚠️ Resume Position (Phase 1) — নিচের দুটো method।
  // ═══════════════════════════════════════════════════════════════

  /// Resume Position — current track-এর playback position হালকা ভাবে
  /// persist করা। saveQueue()-এর মতো পুরো queue delete+reinsert করে না,
  /// শুধু isCurrent=true row-এর lastPositionMs আপডেট করে — তাই এটা
  /// প্রতি কয়েক সেকেন্ড অন্তর (throttled, caller-side, দেখো
  /// MusicPlayerRepository._maybePersistPosition) কল করার জন্য যথেষ্ট
  /// সস্তা।
  ///
  /// ⚠️ এখানে `updatedAt` ইচ্ছাকৃতভাবে টাচ করা হচ্ছে না — এটা শুধু একটা
  /// "progress tick", queue reorder/track-change-এর মতো LWW-significant
  /// event না। updatedAt বদলালে Phase 4 cross-device sync-এ প্রতি কয়েক
  /// সেকেন্ড অন্তর এই row-কে "সাম্প্রতিকতম" ধরে অন্য device-এর real
  /// queue-change (যেমন reorder) ভুলবশত পুরনো মনে হতে পারে।
  Future<void> updatePlaybackPosition({
    required String songId,
    required int positionMs,
  }) async {
    final userId = _userId;

    final updated = await (db.update(db.queueItems)
          ..where((t) =>
              t.userId.equals(userId) &
              t.songId.equals(songId) &
              t.isCurrent.equals(true)))
        .write(QueueItemsCompanion(
          lastPositionMs: Value(positionMs),
        ));

    if (updated == 0) {
      AppLogger.playback(
        'updatePlaybackPosition: কোনো matching current-queue row পাওয়া '
        'যায়নি (songId=$songId) — skip',
      );
    }
  }

  /// App restart-এ resume prompt দেখানোর জন্য — বর্তমান user-এর
  /// isCurrent row-এর saved position + songId ফেরত দেয় (থাকলে)।
  Future<({String songId, int positionMs})?>
      getCurrentPlaybackPosition() async {
    final userId = _userId;

    final row = await (db.select(db.queueItems)
          ..where((t) => t.userId.equals(userId) & t.isCurrent.equals(true)))
        .getSingleOrNull();

    if (row == null) return null;
    return (songId: row.songId, positionMs: row.lastPositionMs ?? 0);
  }
}