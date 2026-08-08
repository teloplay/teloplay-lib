import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/library_repository.dart';
import '../../models/history_entry_model.dart';
import '../../models/favorite_model.dart';
import '../../providers/database_provider.dart';
import '../../providers/music_player_provider.dart' show queueRepositoryProvider;

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

/// Continue Listening — সর্বশেষ saved playback position + সেই track-এর
/// metadata।
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
}

final continueListeningProvider =
    FutureProvider.autoDispose<ContinueListeningInfo?>((ref) async {
  final queueRepo = ref.watch(queueRepositoryProvider);
  final saved = await queueRepo.getCurrentPlaybackPosition();
  if (saved == null || saved.positionMs <= 0) return null;

  // ⚠️ Fix: আগে recentlyPlayed (limit 12) list-এর ভেতর songId খুঁজে
  // match করা হতো — history অনেক বেশি হলে সেই গান list-এর বাইরে পড়ে
  // যেত, Hero silently null থাকত। এখন সরাসরি Songs টেবিল থেকে metadata
  // টানা হচ্ছে, recentlyPlayed-এর উপর কোনো নির্ভরতা নেই।
  final db = ref.watch(appDatabaseProvider);
  final song = await (db.select(db.songs)..where((t) => t.id.equals(saved.songId))).getSingleOrNull();
  if (song == null) return null;

  return ContinueListeningInfo(
    songId: song.id,
    title: song.title,
    author: song.author,
    thumbnail: song.thumbnail,
    positionMs: saved.positionMs,
  );
});