import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_engine.dart';
import '../data/repositories/library_repository.dart';
import '../models/history_entry_model.dart';
import '../models/favorite_model.dart';
import 'database_provider.dart';

/// পুরো app-এ single [LibraryRepository] instance — Favorites/Playlists/
/// History/Recently Played সবকিছুর জন্য (পরের ব্যাচে Favorites/Playlists
/// methods একই repository-তে যোগ হবে, provider বদলাবে না)।
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LibraryRepository(db);
});

/// পূর্ণ, raw History — History screen-এর জন্য। FutureProvider.autoDispose
/// ব্যবহার করা হয়েছে recentSearchesProvider-এর মতোই একই কারণে (fresh
/// data দরকার, কিন্তু screen বন্ধ হলে dispose হওয়াই ঠিক)।
///
/// ⚠️ নতুন playback event এলে এই provider নিজে থেকে রিফ্রেশ হয় না —
/// BehaviourTrackingService.recordPlayback() history_screen.dart-এর
/// বাইরে (MusicPlayerRepository-এর ভেতরে) কল হয়, ওই দুই জায়গার মধ্যে
/// সরাসরি সংযোগ নেই। History screen নিজে খোলা হলে/pull-to-refresh
/// করলেই আপডেট হবে (recentSearchesProvider-এর মতো search()-এর ভেতর
/// থেকে সরাসরি invalidate করার সুযোগ এখানে নেই, কারণ playback event
/// আর screen-এর lifecycle সংযুক্ত না) — এটা এখন গ্রহণযোগ্য সীমাবদ্ধতা,
/// ভবিষ্যতে দরকার হলে Stream-based approach বিবেচনা করা যাবে।
final historyProvider =
    FutureProvider.autoDispose<List<HistoryLogEntry>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getHistory();
});

/// Distinct, track-level Recently Played — thumbnail-সহ, Library
/// home/analytics section-এ ব্যবহারের জন্য (পরের ব্যাচে library_screen.dart
/// এটা consume করবে)।
final recentlyPlayedProvider =
    FutureProvider.autoDispose<List<RecentlyPlayedEntry>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getRecentlyPlayed();
});

// ─────────────────────────────────────────────────────────────────────────
// Favorites
// ─────────────────────────────────────────────────────────────────────────

/// সব favorite গানের reactive list — StreamProvider (FutureProvider না),
/// কারণ LibraryRepository.watchFavorites() Drift-এর নিজস্ব `.watch()`
/// ব্যবহার করে — toggleFavorite() কল হলে এই stream নিজে থেকেই নতুন
/// data emit করবে, historyProvider-এর মতো manual ref.invalidate() লাগবে
/// না। .autoDispose ব্যবহার করা হয়নি ইচ্ছাকৃতভাবে — Favorites heart-icon
/// state যেকোনো screen থেকে (music player screen, favorites screen)
/// একসাথে watch হতে পারে, keepAlive থাকলে দুই জায়গায় একই underlying
/// stream subscription পুনর্ব্যবহার হয়।
final favoritesProvider = StreamProvider<List<FavoriteSong>>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchFavorites();
});

/// একটা নির্দিষ্ট গান favorite কিনা — heart icon-এর state দেখাতে।
/// favoritesProvider থেকেই derive করা হচ্ছে (আলাদা DB query না চালিয়ে),
/// তাই এই provider সবসময় favoritesProvider-এর সাথে সিঙ্কে থাকে এবং
/// অতিরিক্ত কোনো DB hit হয় না।
final isFavoriteProvider = Provider.family<bool, String>((ref, songId) {
  final favorites = ref.watch(favoritesProvider).value ?? const [];
  return favorites.any((f) => f.songId == songId);
});

// ─────────────────────────────────────────────────────────────────────────
// Downloaded / Cached Songs (Phase 3 — Smart Cache)
// ─────────────────────────────────────────────────────────────────────────

/// Library-র "Downloaded Songs" section-এর জন্য — cachedLocally=true
/// সব গান, cache size অনুযায়ী descending।
///
/// ⚠️ FutureProvider.autoDispose (historyProvider/recentlyPlayedProvider-
/// এর মতোই) — reactive Stream না হওয়ার কারণ: cache mutation
/// (download/evict) DB-write সরাসরি এই provider-কে জানায় না
/// (CacheService/CacheRepository আলাদা layer, Favorites-এর মতো
/// LibraryRepository-র ভেতর দিয়ে write হয় না)। তাই screen খোলা/
/// pull-to-refresh/ref.invalidate()-এর মাধ্যমেই রিফ্রেশ হবে —
/// downloaded_songs_screen.dart-এ delete-এর পরে explicit
/// `ref.invalidate(cachedSongsProvider)` কল করা হবে, ঠিক
/// historyProvider-এর deleteHistoryEntry() flow-এর মতো।
final cachedSongsProvider =
    FutureProvider.autoDispose<List<CachedSongEntry>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getCachedSongs();
});

// ─────────────────────────────────────────────────────────────────────────
// Albums (Phase 6.5B — flat Songs.albumId grouping, no Albums table yet)
// ─────────────────────────────────────────────────────────────────────────

/// Full track list for a given album — AlbumDetailsScreen-এর একমাত্র
/// data source (দেখো library_repository.dart-এর getSongsByAlbumId()
/// doc-comment — architecture rule: future Albums table এলেও এই
/// provider-এর shape বদলাবে না)।
///
/// .family ব্যবহার করা হয়েছে কারণ albumId route param অনুযায়ী পাল্টায়
/// (isFavoriteProvider-এর মতোই প্যাটার্ন)। .autoDispose — screen বন্ধ
/// হলে dispose হওয়াই ঠিক (historyProvider-এর মতোই কারণ)।
final albumTracksProvider =
    FutureProvider.autoDispose.family<List<SearchResult>, String>(
        (ref, albumId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getSongsByAlbumId(albumId);
});

final artistTracksProvider =
    FutureProvider.autoDispose.family<List<SearchResult>, String>(
        (ref, artistId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getSongsByArtistId(artistId);
});