import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/library_repository.dart';
import '../../models/continue_session.dart';
import '../../models/history_entry_model.dart';
import '../../models/favorite_model.dart';
import '../../providers/database_provider.dart';
import '../../providers/music_player_provider.dart'
    show
        queueRepositoryProvider,
        musicPlayerRepositoryProvider,
        settingsRepositoryProvider;
import '../../services/session/continue_session_manager.dart';

/// Phase 6.5 Batch 2 — Home-এর জন্য প্রয়োজনীয় read-only aggregations।
/// কোনো নতুন write/mutation নেই এই ফাইলে — সব existing repository থেকে
/// পড়া, শুধু Home-screen-specific shape-এ combine করা হচ্ছে।
///
/// ⚠️ Fix: queueRepositoryProvider এখানে নতুন করে define করা হয়নি —
/// music_player_provider.dart-এ ইতিমধ্যেই সংজ্ঞায়িত আছে, সেখান থেকেই
/// import করা হচ্ছে (duplicate-provider compile error এড়াতে)।

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LibraryRepository(db);
});

/// Recently played track list (thumbnail-সহ) — "Recently Added"/
/// "Jump Back In" rail দুটোতেই একই data-source ব্যবহার করা হচ্ছে
/// (roadmap-এ এই দুটো section conceptually কাছাকাছি, আলাদা কোনো
/// "added-at" timestamp Songs টেবিলে নেই বলে "recently added" আসলে
/// "recently played"-এরই আরেকটা framing হিসেবে দেখানো হচ্ছে এই ব্যাচে)।
final recentlyPlayedForHomeProvider =
    FutureProvider.autoDispose<List<RecentlyPlayedEntry>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getRecentlyPlayed(limit: 12);
});

/// Favorites rail — reactive (favorite toggle হলে সাথে সাথে rail
/// আপডেট হবে)।
final favoritesForHomeProvider =
    StreamProvider.autoDispose<List<FavoriteSong>>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchFavorites();
});

/// Most Played rail — Behaviour Tracking play-count থেকে।
final mostPlayedForHomeProvider =
    FutureProvider.autoDispose<List<RecentlyPlayedEntry>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getMostPlayed(limit: 12);
});

/// Downloaded/cached songs rail — Smart Cache-backed।
final cachedSongsForHomeProvider =
    FutureProvider.autoDispose<List<CachedSongEntry>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getCachedSongs();
});

/// Carousel-এর "Top Favorite" card — favorites list-এর প্রথমটা (সর্বশেষ
/// favorite করা)। watchFavorites() আগে থেকেই আছে, শুধু প্রথম item নেওয়া
/// হচ্ছে — নতুন repository method লাগেনি।
final topFavoriteForHomeProvider =
    StreamProvider.autoDispose<FavoriteSong?>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchFavorites().map((list) => list.isEmpty ? null : list.first);
});

// ═══════════════════════════════════════════════════════════════
// ⚠️ v11 Continue Session (Section H) — multi-song resume.
//
// Fix (Phase 0 v11 stabilization): this REPLACES the old single-song
// ContinueListeningInfo/continueListeningProvider pair (roadmap Section H:
// "existing roadmap-এ যেখানেই Resume Playback Position ছিল, সেটাকে এই
// upgraded model দিয়ে replace/extend করতে হবে"). The old provider read
// queueRepo.getCurrentPlaybackPosition() + a raw Songs-table lookup for
// just the current track; ContinueSessionManager reads the SAME
// QueueRepository state but returns the full queue + index + a
// user-facing sourceRail label, matching the "Tum Hi Ho + 4 more songs ·
// From: Daily Mix" card the roadmap specifies. No parallel/duplicate
// system — same QueueRepository backing store as before.
// ═══════════════════════════════════════════════════════════════

final continueSessionManagerProvider = Provider<ContinueSessionManager>((ref) {
  return ContinueSessionManager(
    queueRepository: ref.watch(queueRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
});

final continueSessionProvider =
    FutureProvider.autoDispose<ContinueSession?>((ref) async {
  final manager = ref.watch(continueSessionManagerProvider);
  return manager.checkForResume();
});

/// Single-song projection of [continueSessionProvider], for widgets that
/// predate the multi-song Continue Session model and only need the
/// current track (desktop [FeaturedHeroCard], mobile hero carousel).
/// Kept so those widgets don't need to change — same underlying
/// QueueRepository-backed data, just narrowed to one track's fields.
class ContinueListeningInfo {
  final String songId;
  final String title;
  final String author;
  final String thumbnail;
  final int positionMs;

  const ContinueListeningInfo({
    required this.songId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.positionMs,
  });

  factory ContinueListeningInfo.fromSession(ContinueSession session) =>
      ContinueListeningInfo(
        songId: session.currentSong.videoId,
        title: session.currentSong.title,
        author: session.currentSong.author,
        thumbnail: session.currentSong.thumbnail,
        positionMs: session.currentPosition.inMilliseconds,
      );
}

final continueListeningProvider =
    FutureProvider.autoDispose<ContinueListeningInfo?>((ref) async {
  final session = await ref.watch(continueSessionProvider.future);
  return session == null ? null : ContinueListeningInfo.fromSession(session);
});