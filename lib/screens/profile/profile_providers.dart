import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/cache_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../services/auth_service.dart';

/// ⚠️ Phase 6.5 Batch 6 — Profile screen-এর সব data source এখান থেকে।
/// কোনো নতুন repository তৈরি করা হয়নি এই ব্যাচে — বিদ্যমান
/// LibraryRepository/PlaylistRepository/CacheRepository/AuthService-এর
/// উপর thin aggregation layer হিসেবে providers বসানো হয়েছে (roadmap
/// নীতি: "একই ডেটার উপর ভিন্ন consumer, ভিন্ন shape")।

/// AuthService singleton — providers.dart-এর কোথাও আগে থেকে না থাকলে
/// এখানে নতুন করে বসানো হলো। ইতিমধ্যে project-এ থাকলে duplicate
/// provider name conflict দেখা দিলে এই একটা লাইন সরিয়ে existing
/// import ব্যবহার করলেই যথেষ্ট।
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// বর্তমান user-এর auth state — reactive, Sign Out করলে UI নিজে থেকে
/// আপডেট হবে (Welcome screen redirect ইতিমধ্যে GoRouter auth-redirect
/// দিয়ে হ্যান্ডেল হয়, এই provider শুধু Profile screen-এর নিজস্ব
/// display purpose-এ ব্যবহৃত)।
final authStateProvider = StreamProvider<AuthState>((ref) {
  final service = ref.watch(authServiceProvider);
  return service.authStateChanges;
});

/// CacheRepository singleton reference — অন্য কোনো provider file-এ
/// আগে থেকে থাকলে সেটা reuse করা উচিত; এখানে ধরে নেওয়া হচ্ছে এখনো
/// কোথাও centralized provider হিসেবে নেই।
final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CacheRepository(db);
});

/// ═══════════════════════════════════════════════════════════════
/// Quick Stats — Profile header-এর নিচে grid
/// ═══════════════════════════════════════════════════════════════

class ProfileQuickStats {
  final int totalPlayedSongs;
  final int favoriteSongsCount;
  final int playlistsCount;
  final Duration listeningTimeThisWeek;
  final int cachedSongsCount;

  const ProfileQuickStats({
    required this.totalPlayedSongs,
    required this.favoriteSongsCount,
    required this.playlistsCount,
    required this.listeningTimeThisWeek,
    required this.cachedSongsCount,
  });

  static const empty = ProfileQuickStats(
    totalPlayedSongs: 0,
    favoriteSongsCount: 0,
    playlistsCount: 0,
    listeningTimeThisWeek: Duration.zero,
    cachedSongsCount: 0,
  );
}

/// ⚠️ Total Played Songs — "distinct song listened at least once"
/// অর্থে (Recently Played row count-এর সমান, LibraryRepository-এর
/// getRecentlyPlayed()-এর একই distinct-songId ধারণা ব্যবহার করে, কিন্তু
/// এখানে UI-তে পুরো list দরকার নেই শুধু count) — তাই সরাসরি
/// recentlyPlayedProvider (যদি থাকে) বা library repository-র মাধ্যমে।
/// "This Week" listening-duration-এর জন্য raw HistoryEntries দরকার,
/// তাই এখানে LibraryRepository.getHistory() reuse করে সপ্তাহ-ভিত্তিক
/// filter+sum নিজেই করা হচ্ছে — কোনো নতুন repository method না বানিয়ে
/// (Batch 6 minimal-footprint সিদ্ধান্ত)।
final profileQuickStatsProvider = FutureProvider.autoDispose<ProfileQuickStats>((ref) async {
  final libraryRepo = ref.watch(libraryRepositoryProvider);
  final cacheRepo = ref.watch(cacheRepositoryProvider);

  // Playlists count — playlistsProvider এখনো loading হলে empty ধরে
  // নেওয়া হচ্ছে, stats grid পরে নিজে থেকে rebuild হবে যখন playlists
  // data আসবে (ref.watch এখানে ইচ্ছাকৃতভাবে ব্যবহার হচ্ছে না, কারণ
  // FutureProvider-এর ভেতরে watch করলে playlists বদলালেই পুরো stats
  // future আবার resolve হবে — যেটা কাম্য না, তাই read + fallback)।
  final playlistsAsync = ref.read(playlistsProvider);
  final playlistsCount = playlistsAsync.maybeWhen(
    data: (list) => list.length,
    orElse: () => 0,
  );

  final favorites = await libraryRepo.watchFavorites().first;
  final recentlyPlayed = await libraryRepo.getRecentlyPlayed(limit: 10000);
  final cachedSongs = await cacheRepo.getAllCachedSongs();

  // "This Week" — raw history থেকে গত ৭ দিনের playedDurationMs sum।
  // getHistory() নতুন থেকে পুরনো ক্রমে দেয়, limit বাড়িয়ে যথেষ্ট window
  // cover করা হচ্ছে (২০০০ row বাস্তবসম্মত ceiling, ছোট app-এর জন্য
  // ১ সপ্তাহে এর বেশি session হওয়ার সম্ভাবনা কম)।
  final history = await libraryRepo.getHistory(limit: 2000);
  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  var weeklyMs = 0;
  for (final entry in history) {
    if (entry.playedAt.isBefore(weekAgo)) continue;
    weeklyMs += entry.playedDuration?.inMilliseconds ?? 0;
  }

  return ProfileQuickStats(
    totalPlayedSongs: recentlyPlayed.length,
    favoriteSongsCount: favorites.length,
    playlistsCount: playlistsCount,
    listeningTimeThisWeek: Duration(milliseconds: weeklyMs),
    cachedSongsCount: cachedSongs.length,
  );
});

/// ═══════════════════════════════════════════════════════════════
/// Storage & Cache section
/// ═══════════════════════════════════════════════════════════════

class ProfileStorageInfo {
  final int cachedSongsCount;
  final int totalCacheSizeBytes;

  const ProfileStorageInfo({
    required this.cachedSongsCount,
    required this.totalCacheSizeBytes,
  });

  static const empty = ProfileStorageInfo(cachedSongsCount: 0, totalCacheSizeBytes: 0);
}

final profileStorageInfoProvider = FutureProvider.autoDispose<ProfileStorageInfo>((ref) async {
  final cacheRepo = ref.watch(cacheRepositoryProvider);
  final cachedSongs = await cacheRepo.getAllCachedSongs();

  var totalBytes = 0;
  for (final song in cachedSongs) {
    totalBytes += song.sizeBytes;
  }

  return ProfileStorageInfo(
    cachedSongsCount: cachedSongs.length,
    totalCacheSizeBytes: totalBytes,
  );
});