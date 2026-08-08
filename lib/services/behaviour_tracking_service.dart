import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/logging/app_logger.dart';
import '../data/drift/database.dart';

/// একটা track play session কীভাবে শেষ হলো — HistoryEntries-এর
/// completed/skipped/interrupted state সরাসরি reflect করে।
enum PlaybackOutcome {
  /// গান শেষ পর্যন্ত শোনা হয়েছে (completion fraction >= threshold)
  completed,

  /// user ইচ্ছাকৃতভাবে skip করেছে (next/previous চাপা, বা track পরিবর্তন,
  /// completion threshold-এর আগে)
  skipped,

  /// network/error/app-lifecycle কারণে playback থেমে গেছে — কোনো
  /// user-intent signal না
  interrupted,
}

/// সব Behaviour Tracking capture event-এর single entry point।
///
/// ⚠️ Session-lifecycle পুনর্গঠন (Recently Played / Behaviour Tracking
/// separation) — আগে এই service-এ একটাই `recordPlayback()` মেথড ছিল,
/// যেটা session *শেষ হলে* (skip/completed/interrupted) একটা row
/// insert করত। এর ফলে দুইটা সমস্যা হতো:
///
///   ১. "Recently Played" delayed ছিল — user যতক্ষণ না গান skip/শেষ
///      করছে, ততক্ষণ কোনো row-ই তৈরি হতো না, তাই Recently Played
///      list-এ সাথে সাথে দেখা যেত না (Spotify-এর মতো না)।
///   ২. Recently Played আর Behaviour Tracking একই single insert-এর
///      উপর নির্ভরশীল ছিল — কোনো আলাদা "শুরু হয়েছে" বনাম "কতটুকু
///      শোনা হয়েছে" concept ছিল না।
///
/// এখন দুই ধাপে ভাঙা হয়েছে:
///
///   - `startPlaybackSession()` — playback থ্রেশহোল্ড (৩-৫s) পার হলে
///     কল হয়, একটা নতুন HistoryEntries row insert করে (playedAt =
///     এখন, বাকি সব null/false) এবং তার `id` রিটার্ন করে। এই row
///     তৈরি হওয়া মাত্রই "Recently Played"-এ দেখা যাবে (row-এর
///     অস্তিত্বই যথেষ্ট, completed/skipped যাই হোক না কেন)।
///   - `endPlaybackSession()` — session শেষ হলে (skip/completed/
///     interrupted/dispose) কল হয়, সেই *একই* row-কে update করে
///     (`playedDurationMs`, `completed`, `skipped`)। Play Count/
///     Complete Count/Skip Count metrics এই update-করা column
///     গুলো থেকেই পরে derive হবে (LibraryRepository-এর query-তে,
///     threshold rule অনুযায়ী — কোনো নতুন column/insert লাগে না)।
///
/// যদি threshold পার হওয়ার আগেই session শেষ হয় (৩-৫s-এর আগেই skip),
/// তাহলে `startPlaybackSession()` কখনো কল-ই হয় না — সেই গান Recently
/// Played বা Behaviour Tracking কোনোটাতেই record হবে না, যেটা
/// ইচ্ছাকৃত (roadmap স্পেসিফিকেশন অনুযায়ী)।
///
/// এই service ইচ্ছাকৃতভাবে কোনো repository-তে embed করা হয়নি (Phase
/// 0.9 সিদ্ধান্ত অপরিবর্তিত) — single-responsibility বজায় রাখতে,
/// একাধিক repository (MusicPlayerRepository, LibraryRepository) থেকে
/// আলাদা আলাদা event capture করতে হয় বলে।
class BehaviourTrackingService {
  final AppDatabase _db;
  static const _uuid = Uuid();

  BehaviourTrackingService(this._db);

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  /// একটা নতুন playback session শুরু করা — playback থ্রেশহোল্ড (৩-৫s)
  /// পার হওয়ার পরে MusicPlayerRepository থেকে কল হবে।
  ///
  /// একটা নতুন HistoryEntries row insert করে (playedAt = এখন,
  /// completed/skipped/playedDurationMs সব null/absent) এবং তার
  /// `id` রিটার্ন করে — caller (MusicPlayerRepository) এই id ধরে
  /// রাখবে যাতে session শেষে `endPlaybackSession()`-এ একই row
  /// update করা যায়।
  ///
  /// রিটার্ন `null` মানে row তৈরি হয়নি (userId null, বা DB error) —
  /// caller-এর উচিত এই ক্ষেত্রে `_currentHistoryEntryId` সেট না করা,
  /// যাতে পরবর্তী `endPlaybackSession()` কল silently skip হয়ে যায়।
  Future<String?> startPlaybackSession({required String songId}) async {
    final userId = _userId;
    if (userId == null) {
      // Guest mode-ও Anonymous Auth ব্যবহার করে, তাই এটা অপ্রত্যাশিত —
      // কিন্তু behaviour tracking miss হওয়া critical না (playback
      // flow-কে block করার মতো না), তাই এখানে exception ছোড়া হচ্ছে
      // না, শুধু log করে null রিটার্ন।
      AppLogger.playback(
        'BehaviourTracking: userId null, session শুরু করা হলো না',
      );
      return null;
    }

    try {
      final id = _uuid.v4();
      await _db.into(_db.historyEntries).insert(
            HistoryEntriesCompanion.insert(
              id: id,
              userId: userId,
              songId: songId,
              // completed/skipped/playedDurationMs ইচ্ছাকৃতভাবে absent —
              // session এখনো চলছে, শেষ ফলাফল জানা নেই। playedAt
              // column-এর নিজস্ব withDefault(currentDateAndTime) ব্যবহার
              // হচ্ছে, যেটাই "Recently Played" query-এর ভিত্তি।
            ),
          );

      AppLogger.playback(
        'BehaviourTracking: session started id=$id songId=$songId',
      );
      return id;
    } catch (e) {
      AppLogger.error('BehaviourTracking: startPlaybackSession ব্যর্থ', e);
      return null;
    }
  }

  /// একটা চলমান playback session বন্ধ করা — MusicPlayerRepository
  /// থেকে কল হবে (skip/completed/interrupted/dispose, যেকোনো কারণে
  /// session শেষ হলে)।
  ///
  /// [historyEntryId] হলো `startPlaybackSession()`-এর রিটার্ন করা id —
  /// এই মেথড সেই *একই* row-কে update করে, নতুন row insert করে না।
  ///
  /// Outcome নির্ণয় (completed vs skipped) caller (MusicPlayerRepository)
  /// এর দায়িত্ব — completion fraction (playedDuration/trackDuration vs
  /// ৯৫% threshold) সেখানেই হিসাব হয়, কারণ track duration/position
  /// জানার একমাত্র জায়গা playback layer, এই service না।
  Future<void> endPlaybackSession({
    required String historyEntryId,
    required PlaybackOutcome outcome,
    Duration? playedDuration,
  }) async {
    try {
      final rowsAffected = await (_db.update(_db.historyEntries)
            ..where((t) => t.id.equals(historyEntryId)))
          .write(
        HistoryEntriesCompanion(
          completed: Value(outcome == PlaybackOutcome.completed),
          skipped: Value(outcome == PlaybackOutcome.skipped),
          playedDurationMs: playedDuration != null
              ? Value(playedDuration.inMilliseconds)
              : const Value.absent(),
        ),
      );

      if (rowsAffected == 0) {
        // Row আগে থেকে delete হয়ে গেছে (user history clear করেছে
        // session চলাকালীন) — এটা harmless edge case, শুধু log।
        AppLogger.playback(
          'BehaviourTracking: endPlaybackSession — row not found '
          '(id=$historyEntryId, সম্ভবত আগেই delete হয়েছে)',
        );
        return;
      }

      AppLogger.playback(
        'BehaviourTracking: session ended id=$historyEntryId '
        'outcome=$outcome playedDuration=$playedDuration',
      );
    } catch (e) {
      // Behaviour tracking ব্যর্থ হলেও playback flow-কে প্রভাবিত করা
      // উচিত না — শুধু log করে এগিয়ে যাওয়া।
      AppLogger.error('BehaviourTracking: endPlaybackSession ব্যর্থ', e);
    }
  }

  /// একটা search query capture করা — MusicPlayerRepository.search()
  /// থেকে কল হবে (fire-and-forget)। অপরিবর্তিত (session-lifecycle
  /// পুনর্গঠনের সাথে সম্পর্কিত না)।
  Future<void> recordSearch({
    required String query,
    int? resultCount,
  }) async {
    final userId = _userId;
    if (userId == null) {
      AppLogger.playback('BehaviourTracking: userId null, search capture skip');
      return;
    }

    try {
      await _db.into(_db.searchHistoryEntries).insert(
            SearchHistoryEntriesCompanion.insert(
              id: _uuid.v4(),
              userId: userId,
              query: query,
              resultCount: resultCount != null
                  ? Value(resultCount)
                  : const Value.absent(),
            ),
          );

      AppLogger.playback('BehaviourTracking: search recorded query="$query"');
    } catch (e) {
      AppLogger.error('BehaviourTracking: recordSearch ব্যর্থ', e);
    }
  }

  // Phase 2-এ যোগ হবে: recordFavoriteToggle() (LibraryRepository থেকে)
}