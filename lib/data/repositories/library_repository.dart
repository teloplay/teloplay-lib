import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../core/playback/playback_engine.dart';
import '../../models/history_entry_model.dart';
import '../../models/favorite_model.dart';
import '../../models/search_models.dart';
import '../../services/artwork_resolver.dart';
import '../drift/database.dart';
import 'base_repository.dart';
import 'sync_queue_helper.dart';

/// Extra display metadata not carried on [SearchResult] itself
/// (album/artist/genre) — Phase 6.5B, SongDetailsScreen-এর জন্য।
///
/// albumId/albumName এখন Songs টেবিলের real কলাম থেকে আসে (Phase 6.5B
/// step 3 migration ল্যান্ড হয়ে গেছে — songs_table.dart দেখো)। এখনো
/// সাধারণত null-ই আসবে যেহেতু কোনো caller এখনো এই field populate
/// করছে না (Album Details Screen implement হওয়ার অপেক্ষায়), কিন্তু
/// এটা এখন data-availability-এর প্রশ্ন, schema-এর সীমাবদ্ধতা না।
class SongMetadata {
  final String? genre;
  final String? artistId;
  final String? albumId;
  final String? albumName;

  const SongMetadata({
    this.genre,
    this.artistId,
    this.albumId,
    this.albumName,
  });
}

/// Favorites, History, এবং Most Played — এই তিনটা related concern
/// একটা repository-তে রাখা হচ্ছে যেহেতু এরা একে অপরের সাথে ঘনিষ্ঠভাবে
/// জড়িত (favorite/history দুটোই songs টেবিলের উপর নির্ভরশীল)।
///
/// Phase 0: শুধু structure/constructor ঠিক করা হয়েছিল।
/// Phase 2 (batch 1): History + Recently Played CRUD/query logic যোগ।
/// Phase 2 (batch 2): Favorites CRUD যোগ।
/// এই ব্যাচ (session-lifecycle রিফ্যাক্টর): getBehaviourStats() যোগ —
/// Play/Skip/Complete Count + Listen Duration, derived metrics।
/// Most Played এখনো TODO (Phase 7+)।
/// Phase 6.5B: Song Details support — getPlayableSongById()/
/// getSongMetadata() যোগ (বেয়ার deep-link fallback-এর জন্য)।
///
/// _userId getter — QueueRepository/SearchHistoryRepository-এর একই
/// multi-user-scoped pattern অনুসরণ করা হয়েছে (Guest mode-ও Anonymous
/// Auth ব্যবহার করে বলে সবসময় real uid থাকা উচিত; না থাকলে সেটা bug,
/// তাই silent-null না করে explicit StateError)।
///
/// লেখা (History insert/update): এখন BehaviourTrackingService-এর
/// `startPlaybackSession()`/`endPlaybackSession()` এর মাধ্যমে হয়
/// (session-lifecycle পুনর্গঠন — আগে single `recordPlayback()` ছিল,
/// এখন insert-once-at-start + update-later-at-end দুই ধাপে)। এই
/// repository এখনও ইচ্ছাকৃতভাবে History-তে write করে না (Favorites
/// ছাড়া), শুধু পড়ে/aggregate করে — SearchHistoryRepository-এর সাথে
/// একই read-only নীতি সামঞ্জস্যপূর্ণ। SyncQueueHelper তাই History/
/// Behaviour Tracking অংশে ব্যবহৃত হচ্ছে না (read-only) — Favorites
/// অংশে (যেখানে write হয়) ব্যবহৃত হচ্ছে।
class LibraryRepository extends BaseRepository {
  final SyncQueueHelper _syncQueue;
  final ArtworkResolver _artworkResolver;

  LibraryRepository(AppDatabase db)
      : _syncQueue = SyncQueueHelper(db),
        _artworkResolver = ArtworkResolver(db),
        super(db);

  String get _userId {
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) {
      throw StateError(
        'LibraryRepository: কোনো authenticated user নেই। '
        'Guest mode-ও Anonymous Auth ব্যবহার করে, তাই এটা অপ্রত্যাশিত।',
      );
    }
    return id;
  }

  // ═══════════════════════════════════════════════════════════════
  // History (raw chronological log)
  // ═══════════════════════════════════════════════════════════════

  /// পূর্ণ, raw play-history — নতুন থেকে পুরনো ক্রমে, প্রতিটা play
  /// event আলাদা row হিসেবে (একই গান একাধিকবার শোনা হলে একাধিক entry
  /// আসবে)। History screen (chronological list)-এর জন্য।
  Future<List<HistoryLogEntry>> getHistory({int limit = 100}) async {
    final userId = _userId;

    final rows = await (db.select(db.historyEntries)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.playedAt)])
          ..limit(limit))
        .join([
      innerJoin(
        db.songs,
        db.songs.id.equalsExp(db.historyEntries.songId),
      ),
    ]).get();

    return rows.map((row) {
      final entry = row.readTable(db.historyEntries);
      final song = row.readTable(db.songs);

      return HistoryLogEntry(
        id: entry.id,
        songId: song.id,
        title: song.title,
        author: song.author,
        thumbnail: song.thumbnail,
        playedAt: entry.playedAt,
        completed: entry.completed,
        skipped: entry.skipped ?? false,
        playedDuration: entry.playedDurationMs != null
            ? Duration(milliseconds: entry.playedDurationMs!)
            : null,
      );
    }).toList();
  }

  /// একটা single History entry মুছে ফেলা (swipe-to-delete/explicit delete
  /// button) — historyEntryId হলো HistoryEntries.id (UUID), songId না,
  /// কারণ একই songId-র একাধিক row থাকতে পারে, ভুল করে সবগুলো মুছে
  /// ফেলা ঠিক হবে না।
  Future<void> deleteHistoryEntry(String historyEntryId) async {
    final userId = _userId;
    await (db.delete(db.historyEntries)
          ..where((t) =>
              t.userId.equals(userId) & t.id.equals(historyEntryId)))
        .go();
  }

  /// পুরো History clear করা (settings/privacy action-এর জন্য)।
  Future<void> clearHistory() async {
    final userId = _userId;
    await (db.delete(db.historyEntries)
          ..where((t) => t.userId.equals(userId)))
        .go();
    AppLogger.playback('History cleared for user');
  }

  // ═══════════════════════════════════════════════════════════════
  // Recently Played (distinct, track-level, thumbnail-সহ)
  // ═══════════════════════════════════════════════════════════════

  /// Distinct "Recently Played" — একই গান একাধিকবার শোনা হয়ে থাকলেও
  /// সবচেয়ে সাম্প্রতিক play-timestamp অনুযায়ী একবারই দেখানো হয়
  /// (SearchHistoryRepository.getRecentSearches()-এর GROUP BY প্যাটার্ন
  /// অনুসরণ করে, query-এর বদলে songId দিয়ে)।
  ///
  /// completed/skipped filter ইচ্ছাকৃতভাবে করা হয়নি — এখানে "কী শোনা
  /// হয়েছে" দেখানো হচ্ছে, "কী শেষ পর্যন্ত শোনা হয়েছে" না। Skip করা
  /// গানও "recently played"-এর অংশ (Spotify-ও তাই করে)। এই query-এর
  /// ভিত্তি HistoryEntries row-এর *অস্তিত্ব* — session-lifecycle
  /// পুনর্গঠনের পর playback থ্রেশহোল্ড (৩-৫s) পার হলেই row তৈরি হয়ে
  /// যায় (BehaviourTrackingService.startPlaybackSession()), গান শেষ/
  /// skip হওয়ার আগেই — তাই এই query কোনো পরিবর্তন ছাড়াই সঠিক থাকে।
  Future<List<RecentlyPlayedEntry>> getRecentlyPlayed({int limit = 20}) async {
    final userId = _userId;

    final history = db.historyEntries;
    final maxPlayedAt = history.playedAt.max();

    final groupedQuery = db.selectOnly(history)
      ..addColumns([history.songId, maxPlayedAt])
      ..where(history.userId.equals(userId))
      ..groupBy([history.songId])
      ..orderBy([OrderingTerm.desc(maxPlayedAt)])
      ..limit(limit);

    final groupedRows = await groupedQuery.get();

    if (groupedRows.isEmpty) return [];

    // songId → lastPlayedAt ম্যাপ বানিয়ে, তারপর Songs টেবিল থেকে
    // metadata (title/author/thumbnail) আলাদা করে fetch করা হচ্ছে —
    // GROUP BY + JOIN একসাথে করলে Drift-এ aggregate column আর
    // non-aggregate joined column একসাথে সঠিকভাবে map করা জটিল হয়ে
    // যেত, তাই দুই ধাপে করা হচ্ছে (২য় query ছোট, শুধু limit-টা songId,
    // খরচ নগণ্য)।
    final songIds = <String>[];
    final lastPlayedMap = <String, DateTime>{};
    for (final row in groupedRows) {
      final songId = row.read(history.songId)!;
      songIds.add(songId);
      lastPlayedMap[songId] = row.read(maxPlayedAt)!;
    }

    final songRows = await (db.select(db.songs)
          ..where((t) => t.id.isIn(songIds)))
        .get();

    final songsById = {for (final s in songRows) s.id: s};

    final result = <RecentlyPlayedEntry>[];
    for (final songId in songIds) {
      final song = songsById[songId];
      if (song == null) continue; // orphaned history row-এর জন্য defensive
      result.add(RecentlyPlayedEntry(
        songId: song.id,
        title: song.title,
        author: song.author,
        thumbnail: song.thumbnail,
        lastPlayedAt: lastPlayedMap[songId]!,
      ));
    }

    // songIds ইতিমধ্যেই lastPlayedAt descending ক্রমে (groupedQuery থেকে),
    // তাই result-ও একই ক্রম বজায় রাখে — আলাদা করে আবার sort করার দরকার নেই।
    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  // Song Details support (Phase 6.5B)
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ এগুলো ইচ্ছাকৃতভাবে থিন/read-only — নতুন sync logic নেই, নতুন
  // টেবিল নেই। `getSongMetadata()` Songs row-এ এখন যা আছে তাই পড়ে
  // (genre/artistId Phase 0.9 থেকেই আছে; albumId/albumName Phase 6.5B
  // step 3 migration-এ যোগ হয়েছে)। কোনো caller এখনো album data populate
  // করছে না, তাই সাধারণত null-ই আসবে — যেটা SongMetadata আগে থেকেই
  // nullable হিসেবে মডেল করে রেখেছে এবং SongDetailsScreen সংশ্লিষ্ট UI
  // অংশ লুকিয়ে সেটা handle করে, data fake করে না।

  /// Minimal playable [SearchResult] reconstructed from whatever is
  /// currently persisted in the Songs table for [songId]. Used by
  /// SongDetailsScreen ONLY when opened via a bare deep link with no
  /// in-memory track data passed in (normal navigation from a list
  /// always passes the track directly, avoiding this lookup).
  ///
  /// Returns null if no Songs row exists for this id (e.g. a stale/
  /// invalid deep link) — caller shows an error state, never guesses.
  Future<SearchResult?> getPlayableSongById(String songId) async {
    final row = await (db.select(db.songs)
          ..where((t) => t.id.equals(songId)))
        .getSingleOrNull();

    if (row == null) return null;

    return SearchResult(
  videoId: row.id,
  title: row.title,
  author: row.author,
  thumbnail: row.thumbnail,
  duration: row.durationSeconds != null
      ? Duration(seconds: row.durationSeconds!)
      : null,
  artistId: row.artistId,
  albumId: row.albumId,
  albumName: row.albumName,
);
  }

  /// Extra display metadata not carried on [SearchResult] itself
  /// (album/artist/genre) — এগুলো শুধু persisted Songs row-এই থাকে।
  /// Returns null if no row exists (mirrors [getPlayableSongById]).
  Future<SongMetadata?> getSongMetadata(String songId) async {
    final row = await (db.select(db.songs)
          ..where((t) => t.id.equals(songId)))
        .getSingleOrNull();

    if (row == null) return null;

    return SongMetadata(
      genre: row.genre,
      artistId: row.artistId,
      // albumId/albumName: Phase 6.5B step 3 migration ল্যান্ড হয়ে
      // গেছে (songs_table.dart-এ কলাম যোগ হয়েছে) — এখন সরাসরি row
      // থেকে পড়া হচ্ছে। কোনো caller এখনো এই field populate করছে না
      // (Album Details Screen implement হওয়ার পর data source
      // integration সাপেক্ষে ভরাট হবে), তাই আপাতত সবসময় null আসবে —
      // কিন্তু এটা এখন "column নেই" না, "data নেই" (schema সম্পূর্ণ)।
      albumId: row.albumId,
      albumName: row.albumName,
    );
  }

  /// Full track list for an album — all Songs rows sharing this
  /// [albumId], ordered stably (by [Songs.addedAt] ascending, since
  /// there's no dedicated track-number column — albumId/albumName are
  /// flat columns on Songs, not a normalized Albums/AlbumTracks schema).
  ///
  /// ⚠️ Architecture note (Phase 6.5B locked decision): this is the ONLY
  /// place AlbumDetailsScreen sources track data from. If a future
  /// Albums table replaces the flat Songs.albumId/albumName columns,
  /// only this method's internals change — the return type
  /// (List<SearchResult>) and signature stay the same, so the UI layer
  /// never needs to know which schema shape is backing it.
  ///
  /// Returns an empty list if no Songs row currently has this albumId
  /// (e.g. no caller has populated album metadata yet, or a stale/
  /// invalid album id) — caller shows an empty-state, never fakes data.
  Future<List<SearchResult>> getSongsByAlbumId(String albumId) async {
    final rows = await (db.select(db.songs)
          ..where((t) => t.albumId.equals(albumId))
          ..orderBy([(t) => OrderingTerm.asc(t.addedAt)]))
        .get();

    return rows
        .map((row) => SearchResult(
              videoId: row.id,
              title: row.title,
              author: row.author,
              thumbnail: row.thumbnail,
              duration: row.durationSeconds != null
                  ? Duration(seconds: row.durationSeconds!)
                  : null,
            ))
        .toList();
  }

  Future<List<SearchResult>> getSongsByArtistId(String artistId) async {
    final rows = await (db.select(db.songs)
          ..where((t) => t.artistId.equals(artistId))
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]))
        .get();

    return rows
        .map((row) => SearchResult(
              videoId: row.id,
              title: row.title,
              author: row.author,
              thumbnail: row.thumbnail,
              duration: row.durationSeconds != null
                  ? Duration(seconds: row.durationSeconds!)
                  : null,
            ))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════
  // Global Search — Albums / Artists (Phase 6.5B)
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ No dedicated Albums/Artists table exists yet — both methods
  // derive results by grouping Songs rows (distinct albumId/artistId),
  // matching [query] against the display name (albumName/author) with
  // a case-insensitive LIKE. Artwork comes from [ArtworkResolver]
  // (first matching song's thumbnail), never invented.
  //
  // Rows with a null albumId/artistId are excluded — they can't be
  // grouped into any album/artist, and showing them would misrepresent
  // ungrouped songs as belonging to some inferred entity.
  //
  // Returns an empty list if nothing matches — caller (SearchController)
  // hides the section entirely rather than showing an empty placeholder
  // (see search_provider.dart MultiSearchState doc-comment).

  /// Distinct albums whose [albumName] matches [query] (case-insensitive
  /// substring). Grouping is done in Dart after a single filtered
  /// Songs query — expected result set is small (a handful of albums
  /// per query), so this avoids a more complex SQL GROUP BY-with-LIKE.
  Future<List<AlbumSearchResult>> searchAlbums(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final rows = await (db.select(db.songs)
          ..where((t) =>
              t.albumId.isNotNull() &
              t.albumName.isNotNull() &
              t.albumName.lower().contains(trimmed.toLowerCase())))
        .get();

    final seen = <String, ({String name, String? artist})>{};
    for (final row in rows) {
      final albumId = row.albumId;
      if (albumId == null) continue;
      seen.putIfAbsent(
        albumId,
        () => (name: row.albumName ?? '', artist: row.author),
      );
    }

    final results = <AlbumSearchResult>[];
    for (final entry in seen.entries) {
      final artwork = await _artworkResolver.resolveAlbumArtwork(entry.key);
      results.add(AlbumSearchResult(
        albumId: entry.key,
        albumName: entry.value.name,
        artistName: entry.value.artist,
        artworkUrl: artwork,
      ));
    }

    return results;
  }

  /// Distinct artists whose display name ([Songs.author]) matches
  /// [query] (case-insensitive substring), grouped by [Songs.artistId].
  /// Same Dart-side grouping rationale as [searchAlbums].
  Future<List<ArtistSearchResult>> searchArtists(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final rows = await (db.select(db.songs)
          ..where((t) =>
              t.artistId.isNotNull() &
              t.author.lower().contains(trimmed.toLowerCase())))
        .get();

    final seen = <String, String>{}; // artistId -> artistName
    for (final row in rows) {
      final artistId = row.artistId;
      if (artistId == null) continue;
      seen.putIfAbsent(artistId, () => row.author);
    }

    final results = <ArtistSearchResult>[];
    for (final entry in seen.entries) {
      final artwork = await _artworkResolver.resolveArtistArtwork(entry.key);
      results.add(ArtistSearchResult(
        artistId: entry.key,
        artistName: entry.value,
        artworkUrl: artwork,
      ));
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════
  // Behaviour Tracking (derived metrics — কোনো নতুন insert না)
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ Play Count এখানে "session recorded হয়েছে" মানে না — সেটা তো
  // getRecentlyPlayed()/row-অস্তিত্বেই বোঝা যায় (থ্রেশহোল্ড ৩-৫s পার
  // হলেই row তৈরি হয়ে যায়)। Play Count-এর জন্য আলাদা, কড়া threshold
  // দরকার (৩০s বা ৫০% duration, যেটা বড়) — কারণ "user শুনেছে" (Recently
  // Played) আর "user meaningfully শুনেছে" (Play Count/Behaviour
  // Tracking) দুইটা আলাদা concept, roadmap স্পেসিফিকেশন অনুযায়ী।
  //
  // Duration না জানা থাকলে (Songs.durationSeconds null) ৫০% fraction
  // হিসাব করা যায় না — সেক্ষেত্রে শুধু ৩০s fixed threshold দিয়েই
  // সিদ্ধান্ত নেওয়া হচ্ছে (max(30s, 50%×duration)-এর duration-জানা-না
  // থাকা fallback)।

  static const _playCountMinDuration = Duration(seconds: 30);

  /// একটা গানের জন্য Behaviour Tracking summary — Play Count, Skip
  /// Count, Complete Count, মোট Listen Duration। LibraryScreen-এর
  /// "Most Played" বা future Statistics section-এর জন্য।
  Future<BehaviourStats> getBehaviourStats({required String songId}) async {
    final userId = _userId;

    final song = await (db.select(db.songs)
          ..where((t) => t.id.equals(songId)))
        .getSingleOrNull();
    final trackDuration = song?.durationSeconds != null
        ? Duration(seconds: song!.durationSeconds!)
        : null;

    final rows = await (db.select(db.historyEntries)
          ..where((t) =>
              t.userId.equals(userId) & t.songId.equals(songId)))
        .get();

    var playCount = 0;
    var skipCount = 0;
    var completeCount = 0;
    var totalListenedMs = 0;

    for (final row in rows) {
      final playedMs = row.playedDurationMs;
      if (playedMs == null) {
        // Session কখনো শেষ হয়নি বলে update হয়নি (crash/অস্বাভাবিক
        // termination) — Recently Played-এ গোনা হয়েছে (row তো
        // আছেই), কিন্তু Behaviour Tracking metrics-এ skip করা হচ্ছে,
        // কারণ actual listened duration অজানা।
        continue;
      }

      totalListenedMs += playedMs;

      final playedDuration = Duration(milliseconds: playedMs);
      final playCountThreshold = trackDuration != null
          ? Duration(
              milliseconds: (trackDuration.inMilliseconds * 0.5)
                  .clamp(
                    _playCountMinDuration.inMilliseconds,
                    double.infinity,
                  )
                  .toInt(),
            )
          : _playCountMinDuration;

      if (playedDuration >= playCountThreshold) {
        playCount++;
      }

      if (row.completed == true) {
        completeCount++;
      } else if (row.skipped == true) {
        skipCount++;
      }
      // completed=false, skipped=false/null (interrupted) — কোনো
      // count-এ যোগ হয় না, শুধু totalListenedMs-এ অবদান রাখে।
    }

    return BehaviourStats(
      songId: songId,
      playCount: playCount,
      skipCount: skipCount,
      completeCount: completeCount,
      totalListenDuration: Duration(milliseconds: totalListenedMs),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Favorites
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ এখানে write হচ্ছে (History-এর মতো read-only না), তাই প্রতিটা
  // mutation-এর পর SyncQueueHelper.enqueue() কল করা হচ্ছে — roadmap-এর
  // offline-first নীতি অনুযায়ী (Drift instant write → UI instant
  // update → Sync Queue entry → background push, Phase 4-এ)।
  // QueueRepository.saveQueue()-এর একই pattern অনুসরণ করা হয়েছে।

  /// একটা গান favorite করা — songId + প্রয়োজনীয় metadata caller থেকে
  /// দিতে হবে (Songs টেবিলে upsert করার জন্য, ঠিক QueueRepository-এর
  /// মতো — কারণ favorite যেকোনো SearchResult-এর উপরেই করা যেতে পারে,
  /// যেটা এখনো Songs টেবিলে নাও থাকতে পারে)।
  Future<void> addFavorite({
    required String songId,
    required String title,
    required String author,
    required String thumbnail,
    int? durationSeconds,
  }) async {
    final userId = _userId;

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

    await db.into(db.favorites).insertOnConflictUpdate(
          FavoritesCompanion.insert(userId: userId, songId: songId),
        );

    AppLogger.playback('Favorite added: songId=$songId');

    await _syncQueue.enqueue(
      entityType: 'favorite',
      entityId: '$userId:$songId',
      action: 'create',
      payload: {'songId': songId},
    );
  }

  /// একটা গান favorite থেকে সরানো।
  Future<void> removeFavorite(String songId) async {
    final userId = _userId;

    await (db.delete(db.favorites)
          ..where((t) => t.userId.equals(userId) & t.songId.equals(songId)))
        .go();

    AppLogger.playback('Favorite removed: songId=$songId');

    await _syncQueue.enqueue(
      entityType: 'favorite',
      entityId: '$userId:$songId',
      action: 'delete',
      payload: {'songId': songId},
    );
  }

  /// একটা গান বর্তমানে favorite কিনা — one-off check (যেমন play screen-এ
  /// heart icon-এর initial state বসাতে, যদি Stream ব্যবহার না করে
  /// সরাসরি চেক করতে চাওয়া হয়)।
  Future<bool> isFavorite(String songId) async {
    final userId = _userId;
    final row = await (db.select(db.favorites)
          ..where((t) => t.userId.equals(userId) & t.songId.equals(songId)))
        .getSingleOrNull();
    return row != null;
  }

  /// Favorite/unfavorite টগল করা — MusicPlayerScreen-এর heart button-এর
  /// জন্য সবচেয়ে সুবিধাজনক single entry point (caller-কে আগে থেকে
  /// isFavorite জানার দরকার নেই, নিজেই চেক করে সিদ্ধান্ত নেয়)।
  Future<bool> toggleFavorite({
    required String songId,
    required String title,
    required String author,
    required String thumbnail,
    int? durationSeconds,
  }) async {
    final alreadyFavorite = await isFavorite(songId);

    if (alreadyFavorite) {
      await removeFavorite(songId);
      return false;
    } else {
      await addFavorite(
        songId: songId,
        title: title,
        author: author,
        thumbnail: thumbnail,
        durationSeconds: durationSeconds,
      );
      return true;
    }
  }

  /// সব favorite গান, thumbnail-সহ, নতুন থেকে পুরনো (সর্বশেষ favorite
  /// করা প্রথমে) — reactive Stream, Favorite toggle হওয়ামাত্র UI নিজে
  /// থেকে আপডেট হয়ে যাবে (Drift-এর নিজস্ব `.watch()`, QueueRepository-এর
  /// মতো manual invalidate লাগে না)।
  Stream<List<FavoriteSong>> watchFavorites() {
    final userId = _userId;

    final query = (db.select(db.favorites)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .join([
      innerJoin(db.songs, db.songs.id.equalsExp(db.favorites.songId)),
    ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final fav = row.readTable(db.favorites);
        final song = row.readTable(db.songs);
        return FavoriteSong(
          songId: song.id,
          title: song.title,
          author: song.author,
          thumbnail: song.thumbnail,
          addedAt: fav.createdAt,
        );
      }).toList();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Downloaded / Cached Songs (Phase 3 — Smart Cache)
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ এটা CacheRepository.getAllCachedSongs()-এর থেকে ইচ্ছাকৃতভাবে
  // আলাদা query — CacheRepository শুধু (videoId, cachePath, sizeBytes)
  // tuple দেয় (CacheService-এর internal filesystem-reconciliation-এর
  // জন্য, cache/repositories ডোমেইনের ভেতরেই), যেখানে এই method
  // Library UI-র জন্য title/author/thumbnail-সহ পূর্ণ metadata দেয় —
  // ঠিক getRecentlyPlayed()/watchFavorites()-এর মতোই raw row-কে
  // UI-friendly shape-এ map করে। দুই জায়গায় ডুপ্লিকেট মনে হতে পারে,
  // কিন্তু concern আলাদা: CacheRepository = cache bookkeeping,
  // LibraryRepository = UI-facing library views (roadmap-এর "একই
  // ডেটার উপর ভিন্ন consumer, ভিন্ন shape" নীতি অন্য জায়গাতেও
  // অনুসরণ করা হয়েছে, যেমন History vs Recently Played)।
  //
  // Sort: সবচেয়ে বড় cache size আগে — Library-তে user সাধারণত storage
  // consciousness নিয়ে এই section দেখে ("কী বেশি জায়গা নিচ্ছে"),
  // chronological order (কখন cache হয়েছে) এখানে কম প্রাসঙ্গিক (সেই
  // timestamp আলাদা কোনো column-এই নেই, Songs টেবিলে cachedAt নেই)।
  Future<List<CachedSongEntry>> getCachedSongs() async {
    final rows = await (db.select(db.songs)
          ..where((t) => t.cachedLocally.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.cacheSizeBytes)]))
        .get();

    return rows
        .where((r) => r.cacheSizeBytes != null)
        .map((r) => CachedSongEntry(
              songId: r.id,
              title: r.title,
              author: r.author,
              thumbnail: r.thumbnail,
              cacheSizeBytes: r.cacheSizeBytes!,
            ))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════
  // Most Played (bring-forward from Phase 7+ TODO — Home rail-এর
  // জন্য দরকার হয়ে পড়ায় এখনই লেখা হলো, getBehaviourStats()-এর একই
  // play-count থ্রেশহোল্ড লজিক পুরো library জুড়ে aggregate করে)
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ Per-song getBehaviourStats() N+1 query এড়াতে এই method সরাসরি
  // SQL-level aggregation করে না (Drift-এ conditional-count expression
  // জটিল) — বরং সব history row একবারে পড়ে Dart-এ group করে। User-level
  // history সাধারণত কয়েক হাজার row-এর বেশি হওয়ার কথা না এই স্টেজে,
  // তাই performance concern নয়। বড় হলে (Phase 7+ পূর্ণ implementation-এ)
  // SQL aggregate query-তে migrate করা যাবে।
  Future<List<RecentlyPlayedEntry>> getMostPlayed({int limit = 20}) async {
    final userId = _userId;

    final rows = await (db.select(db.historyEntries)
          ..where((t) => t.userId.equals(userId)))
        .get();

    // songId → (playCount, durationMs জানার জন্য) গোনা
    final durationCache = <String, Duration?>{};
    final playCounts = <String, int>{};

    for (final row in rows) {
      final playedMs = row.playedDurationMs;
      if (playedMs == null) continue;

      var trackDuration = durationCache[row.songId];
      if (!durationCache.containsKey(row.songId)) {
        final song = await (db.select(db.songs)
              ..where((t) => t.id.equals(row.songId)))
            .getSingleOrNull();
        trackDuration = song?.durationSeconds != null
            ? Duration(seconds: song!.durationSeconds!)
            : null;
        durationCache[row.songId] = trackDuration;
      }

      final playedDuration = Duration(milliseconds: playedMs);
      final threshold = trackDuration != null
          ? Duration(
              milliseconds: (trackDuration.inMilliseconds * 0.5)
                  .clamp(_playCountMinDuration.inMilliseconds, double.infinity)
                  .toInt(),
            )
          : _playCountMinDuration;

      if (playedDuration >= threshold) {
        playCounts[row.songId] = (playCounts[row.songId] ?? 0) + 1;
      }
    }

    if (playCounts.isEmpty) return [];

    final sortedIds = playCounts.keys.toList()
      ..sort((a, b) => playCounts[b]!.compareTo(playCounts[a]!));
    final topIds = sortedIds.take(limit).toList();

    final songRows = await (db.select(db.songs)..where((t) => t.id.isIn(topIds))).get();
    final songsById = {for (final s in songRows) s.id: s};

    final result = <RecentlyPlayedEntry>[];
    for (final songId in topIds) {
      final song = songsById[songId];
      if (song == null) continue;
      result.add(RecentlyPlayedEntry(
        songId: song.id,
        title: song.title,
        author: song.author,
        thumbnail: song.thumbnail,
        lastPlayedAt: DateTime.now(), // ⚠️ placeholder — এই field Most Played context-এ অপ্রাসঙ্গিক, শুধু RecentlyPlayedEntry shape reuse করার জন্য
      ));
    }

    return result;
  }
}