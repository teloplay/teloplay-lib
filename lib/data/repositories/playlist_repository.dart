import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../models/playlist_model.dart';
import '../../models/search_models.dart';
import '../drift/database.dart';
import 'base_repository.dart';
import 'sync_queue_helper.dart';

/// Playlist-সংক্রান্ত সব CRUD/query/ordering logic — LibraryRepository
/// থেকে ইচ্ছাকৃতভাবে আলাদা রাখা হয়েছে।
///
/// ⚠️ Design সিদ্ধান্ত (developer অনুরোধে): Playlists একটা independent,
/// বড় feature — নিজস্ব CRUD, item-ordering, playlist-song relationship,
/// ভবিষ্যতে sync/statistics/recommendation/collaboration সম্ভাবনা আছে।
/// LibraryRepository-কে History/Recently-Played/Most-Played/Favorites-এ
/// focused রাখা হচ্ছে যাতে Phase 4 sync-এর সময় দুটো repository আলাদা,
/// পরিষ্কার responsibility-তে থাকে — একসাথে থাকলে ভবিষ্যতে বড় refactor
/// লাগত।
///
/// _userId getter — অন্য সব repository-র (QueueRepository,
/// LibraryRepository, SearchHistoryRepository) একই multi-user-scoped
/// pattern অনুসরণ করা হয়েছে।
///
/// Sync: প্রতিটা mutation (create/rename/delete playlist, add/remove/
/// reorder item) SyncQueueHelper.enqueue() কল করে — Phase 4-এ offline-
/// first background sync-এর জন্য প্রস্তুত (QueueRepository.saveQueue()/
/// LibraryRepository.addFavorite()-এর একই pattern)।
class PlaylistRepository extends BaseRepository {
  final SyncQueueHelper _syncQueue;
  static const _uuid = Uuid();

  PlaylistRepository(AppDatabase db)
      : _syncQueue = SyncQueueHelper(db),
        super(db);

  String get _userId {
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) {
      throw StateError(
        'PlaylistRepository: কোনো authenticated user নেই। '
        'Guest mode-ও Anonymous Auth ব্যবহার করে, তাই এটা অপ্রত্যাশিক।',
      );
    }
    return id;
  }

  // ═══════════════════════════════════════════════════════════════
  // Playlist CRUD
  // ═══════════════════════════════════════════════════════════════

  /// নতুন playlist তৈরি করা — খালি (কোনো item ছাড়া) শুরু হয়, id রিটার্ন
  /// করে যাতে caller চাইলে সাথে সাথে item add করা শুরু করতে পারে।
  Future<String> createPlaylist({required String name}) async {
    final userId = _userId;
    final id = _uuid.v4();

    await db.into(db.playlists).insert(
          PlaylistsCompanion.insert(
            id: id,
            userId: userId,
            name: name,
          ),
        );

    AppLogger.playback('Playlist created: id=$id name="$name"');

    await _syncQueue.enqueue(
      entityType: 'playlist',
      entityId: id,
      action: 'create',
      payload: {'name': name},
    );

    return id;
  }

  /// Playlist-এর নাম বদলানো — updatedAt explicitly set করা হচ্ছে
  /// (QueueRepository.updateCurrentIndex()-এর একই fix-pattern, Drift-এ
  /// `update().write()` নিজে থেকে withDefault trigger করে না)।
  Future<void> renamePlaylist({
    required String playlistId,
    required String newName,
  }) async {
    final userId = _userId;

    final rowsAffected = await (db.update(db.playlists)
          ..where((t) => t.id.equals(playlistId) & t.userId.equals(userId)))
        .write(
      PlaylistsCompanion(
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (rowsAffected == 0) {
      AppLogger.playback(
        'PlaylistRepository: rename ব্যর্থ — playlist পাওয়া যায়নি '
        '(id=$playlistId)',
      );
      return;
    }

    AppLogger.playback('Playlist renamed: id=$playlistId name="$newName"');

    await _syncQueue.enqueue(
      entityType: 'playlist',
      entityId: playlistId,
      action: 'update',
      payload: {'name': newName},
    );
  }

  /// পুরো playlist মুছে ফেলা — PlaylistItems-এর সব row automatically
  /// cascade delete হয়ে যাবে (table-এ `onDelete: KeyAction.cascade`
  /// আগে থেকেই সেট করা আছে, এখানে আলাদা করে item delete করার দরকার
  /// নেই)।
  Future<void> deletePlaylist(String playlistId) async {
    final userId = _userId;

    await (db.delete(db.playlists)
          ..where((t) => t.id.equals(playlistId) & t.userId.equals(userId)))
        .go();

    AppLogger.playback('Playlist deleted: id=$playlistId');

    await _syncQueue.enqueue(
      entityType: 'playlist',
      entityId: playlistId,
      action: 'delete',
      payload: const {},
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Global Search — Playlists (Phase 6.5B)
  // ═══════════════════════════════════════════════════════════════

  /// Playlists whose [name] matches [query] (case-insensitive substring),
  /// user-scoped. Same shape as [PlaylistSummary] (item count + cover
  /// thumbnail), just projected into [PlaylistSearchResult] so the
  /// search layer doesn't need to import full playlist-detail internals.
  ///
  /// Item count / cover thumbnail resolved the same two-step way as
  /// [watchPlaylists] (see its doc-comment) — acceptable here too since
  /// search-matched playlist counts are small.
  Future<List<PlaylistSearchResult>> searchPlaylists(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final userId = _userId;

    final matches = await (db.select(db.playlists)
          ..where((t) =>
              t.userId.equals(userId) &
              t.name.lower().contains(trimmed.toLowerCase())))
        .get();

    final results = <PlaylistSearchResult>[];

    for (final playlist in matches) {
      final firstItem = await (db.select(db.playlistItems)
            ..where((t) => t.playlistId.equals(playlist.id))
            ..orderBy([(t) => OrderingTerm.asc(t.position)])
            ..limit(1))
          .getSingleOrNull();

      final itemCountRow = await (db.selectOnly(db.playlistItems)
            ..addColumns([db.playlistItems.id.count()])
            ..where(db.playlistItems.playlistId.equals(playlist.id)))
          .getSingle();
      final itemCount = itemCountRow.read(db.playlistItems.id.count()) ?? 0;

      String? coverThumbnail;
      if (firstItem != null) {
        final firstSong = await (db.select(db.songs)
              ..where((t) => t.id.equals(firstItem.songId)))
            .getSingleOrNull();
        coverThumbnail = firstSong?.thumbnail;
      }

      results.add(PlaylistSearchResult(
        playlistId: playlist.id,
        name: playlist.name,
        itemCount: itemCount,
        coverThumbnail: coverThumbnail,
      ));
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════
  // Playlist listing (summary — list screen-এর জন্য)
  // ═══════════════════════════════════════════════════════════════

  /// সব playlist, সবচেয়ে সম্প্রতি updated প্রথমে — প্রতিটার item count
  /// + প্রথম item-এর thumbnail (cover) সহ। Reactive Stream, কোনো
  /// playlist create/rename/delete/item-change হলে UI নিজে থেকে
  /// refresh হবে।
  Stream<List<PlaylistSummary>> watchPlaylists() {
    final userId = _userId;

    // ⚠️ Item count + cover thumbnail আলাদা query দিয়ে আনা হচ্ছে
    // (GROUP BY + first-item-thumbnail একসাথে জটিল Drift join হয়ে
    // যেত — LibraryRepository.getRecentlyPlayed()-এর একই দুই-ধাপ
    // pattern অনুসরণ করা হলো)। Playlist সংখ্যা সাধারণত ছোট (কয়েক
    // ডজনের বেশি না), তাই per-playlist ছোট query চালানো এখানে
    // acceptable — বড় স্কেলে গেলে (Phase 4+) একটা batched query-তে
    // অপটিমাইজ করা যাবে।
    final playlistsQuery = (db.select(db.playlists)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]));

    return playlistsQuery.watch().asyncMap((playlists) async {
      final result = <PlaylistSummary>[];

      for (final playlist in playlists) {
        final items = await (db.select(db.playlistItems)
              ..where((t) => t.playlistId.equals(playlist.id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)])
              ..limit(1))
            .get();

        final itemCountRow = await (db.selectOnly(db.playlistItems)
              ..addColumns([db.playlistItems.id.count()])
              ..where(db.playlistItems.playlistId.equals(playlist.id)))
            .getSingle();
        final itemCount =
            itemCountRow.read(db.playlistItems.id.count()) ?? 0;

        String? coverThumbnail;
        if (items.isNotEmpty) {
          final firstSong = await (db.select(db.songs)
                ..where((t) => t.id.equals(items.first.songId)))
              .getSingleOrNull();
          coverThumbnail = firstSong?.thumbnail;
        }

        result.add(PlaylistSummary(
          id: playlist.id,
          name: playlist.name,
          itemCount: itemCount,
          coverThumbnail: coverThumbnail,
          updatedAt: playlist.updatedAt,
        ));
      }

      return result;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Playlist detail (single playlist + ordered items)
  // ═══════════════════════════════════════════════════════════════

  /// একটা playlist-এর পূর্ণ detail — নাম + সব item, position অনুযায়ী
  /// ordered, Songs metadata (title/author/thumbnail) সহ। Reactive
  /// Stream — item add/remove/reorder হলে UI সাথে সাথে আপডেট হয়।
  Stream<PlaylistDetail?> watchPlaylistDetail(String playlistId) {
    final userId = _userId;

    final playlistQuery = (db.select(db.playlists)
      ..where((t) => t.id.equals(playlistId) & t.userId.equals(userId)));

    final itemsQuery = (db.select(db.playlistItems)
          ..where((t) => t.playlistId.equals(playlistId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .join([
      innerJoin(db.songs, db.songs.id.equalsExp(db.playlistItems.songId)),
    ]);

    // দুইটা independent stream (playlist metadata + items) একসাথে
    // combine করা হচ্ছে — যেকোনো একটাতে পরিবর্তন এলেই নতুন
    // PlaylistDetail emit হবে। Stream.asyncMap দিয়ে items query re-run
    // করে সবসময় সর্বশেষ item list নিশ্চিত করা হচ্ছে।
    return playlistQuery.watchSingleOrNull().asyncMap((playlist) async {
      if (playlist == null) return null;

      final itemRows = await itemsQuery.get();
      final items = itemRows.map((row) {
        final item = row.readTable(db.playlistItems);
        final song = row.readTable(db.songs);
        return PlaylistItemEntry(
          itemId: item.id,
          songId: song.id,
          title: song.title,
          author: song.author,
          thumbnail: song.thumbnail,
          position: item.position,
        );
      }).toList();

      return PlaylistDetail(
        id: playlist.id,
        name: playlist.name,
        items: items,
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Playlist items — add / remove / reorder
  // ═══════════════════════════════════════════════════════════════

  /// একটা গান playlist-এ যোগ করা — সবার শেষে (সর্বোচ্চ position + 1)।
  /// Songs টেবিলে upsert করা হচ্ছে (LibraryRepository.addFavorite()-এর
  /// একই কারণ — গানটা এখনো Songs টেবিলে নাও থাকতে পারে, যেকোনো
  /// SearchResult থেকেই সরাসরি playlist-এ add করা যায়)।
  Future<void> addItem({
    required String playlistId,
    required String songId,
    required String title,
    required String author,
    required String thumbnail,
    int? durationSeconds,
  }) async {
    await db.into(db.songs).insertOnConflictUpdate(
          SongsCompanion.insert(
            id: songId,
            title: title,
            author: author,
            thumbnail: thumbnail,
            durationSeconds: durationSeconds != null
                ? Value(durationSeconds)
                : const Value.absent(),
          ),
        );

    final maxPositionRow = await (db.selectOnly(db.playlistItems)
          ..addColumns([db.playlistItems.position.max()])
          ..where(db.playlistItems.playlistId.equals(playlistId)))
        .getSingle();
    final nextPosition =
        (maxPositionRow.read(db.playlistItems.position.max()) ?? -1) + 1;

    final itemId = _uuid.v4();
    await db.into(db.playlistItems).insert(
          PlaylistItemsCompanion.insert(
            id: itemId,
            playlistId: playlistId,
            songId: songId,
            position: nextPosition,
          ),
        );

    await _touchPlaylistUpdatedAt(playlistId);

    AppLogger.playback(
      'Playlist item added: playlistId=$playlistId songId=$songId '
      'position=$nextPosition',
    );

    await _syncQueue.enqueue(
      entityType: 'playlist_item',
      entityId: itemId,
      action: 'create',
      payload: {
        'playlistId': playlistId,
        'songId': songId,
        'position': nextPosition,
      },
    );
  }

  /// একটা গান playlist থেকে সরানো — itemId (PlaylistItems.id) দিয়ে,
  /// songId দিয়ে না (একই গান থিওরিটিক্যালি একাধিকবার থাকতে পারলে ভুল
  /// row মুছে যাওয়া এড়াতে, HistoryEntries-এর একই সতর্কতা)।
  ///
  /// Remove করার পরে বাকি item-গুলোর position "gap-fill" করা হচ্ছে না
  /// ইচ্ছাকৃতভাবে — position শুধু relative ordering বোঝাতে ব্যবহার হয়
  /// (ORDER BY position ASC), মাঝে gap থাকলেও ordering ঠিক থাকে, আর
  /// gap-fill করতে গেলে প্রতিটা remove-এ N-1 row touch করতে হতো
  /// (অপ্রয়োজনীয় write overhead)।
  Future<void> removeItem({
    required String playlistId,
    required String itemId,
  }) async {
    await (db.delete(db.playlistItems)..where((t) => t.id.equals(itemId)))
        .go();

    await _touchPlaylistUpdatedAt(playlistId);

    AppLogger.playback('Playlist item removed: itemId=$itemId');

    await _syncQueue.enqueue(
      entityType: 'playlist_item',
      entityId: itemId,
      action: 'delete',
      payload: {'playlistId': playlistId},
    );
  }

  /// Drag & drop reorder — UI থেকে item-এর নতুন ক্রম (পুরো ordered
  /// itemId list) পাঠানো হবে, এই মেথড সব item-এর position sequentially
  /// (0, 1, 2, ...) নতুন করে লিখে দেয়।
  ///
  /// পুরো list rewrite করা হচ্ছে (শুধু বদলে যাওয়া item না) — কারণ drag
  /// & drop-এর ফলে potentially একাধিক item-এর position বদলে যায় (মাঝে
  /// একটা item সরালে তার আগে/পরের সবগুলোর position shift হয়), তাই
  /// diff বের করার চেয়ে পুরো rewrite সহজ ও নিরাপদ। একটা transaction-এ
  /// করা হচ্ছে যাতে আংশিক-reorder কখনো persist না হয়।
  Future<void> reorderItems({
    required String playlistId,
    required List<String> orderedItemIds,
  }) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedItemIds.length; i++) {
        await (db.update(db.playlistItems)
              ..where((t) => t.id.equals(orderedItemIds[i])))
            .write(PlaylistItemsCompanion(position: Value(i)));
      }
    });

    await _touchPlaylistUpdatedAt(playlistId);

    AppLogger.playback(
      'Playlist reordered: playlistId=$playlistId '
      'itemCount=${orderedItemIds.length}',
    );

    await _syncQueue.enqueue(
      entityType: 'playlist',
      entityId: playlistId,
      action: 'reorder',
      payload: {'orderedItemIds': orderedItemIds},
    );
  }

  /// Playlist-এর updatedAt টাচ করা — item add/remove/reorder হলে
  /// playlist-level updatedAt-ও বদলানো উচিত (watchPlaylists()-এর
  /// "সবচেয়ে সম্প্রতি updated প্রথমে" ordering-এর জন্য, এবং future LWW
  /// sync-এর জন্যও প্রাসঙ্গিক)।
  Future<void> _touchPlaylistUpdatedAt(String playlistId) async {
    await (db.update(db.playlists)..where((t) => t.id.equals(playlistId)))
        .write(PlaylistsCompanion(updatedAt: Value(DateTime.now())));
  }
}