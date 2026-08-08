import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/drift/database.dart';
import '../data/repositories/playlist_repository.dart';
import '../models/playlist_model.dart';
import 'database_provider.dart';

// ⚠️ এই ফাইলটা library_provider.dart-এর favoritesProvider/
// recentlyPlayedProvider-এর একই pattern অনুসরণ করে — শুধু Playlists-এর
// জন্য আলাদা রাখা হয়েছে (PlaylistRepository-ও LibraryRepository থেকে
// ইচ্ছাকৃতভাবে আলাদা, দেখো playlist_repository.dart-এর ক্লাস-লেভেল নোট)।
//
// ⚠️ import 'app_database_provider.dart' — অনুমান করা হচ্ছে project-এ
// ইতিমধ্যে একটা shared `appDatabaseProvider` (AppDatabase singleton)
// আছে, যেটা QueueRepository/LibraryRepository-ও ব্যবহার করে। যদি
// আসল provider file/নাম আলাদা হয়, শুধু এই import path + নিচের
// `ref.watch(appDatabaseProvider)` reference বদলে দিলেই যথেষ্ট, বাকি
// কিছু বদলাতে হবে না।

/// PlaylistRepository singleton — app-এর যেকোনো জায়গা থেকে inject
/// করার জন্য।
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PlaylistRepository(db);
});

/// সব playlist-এর summary list — reactive, PlaylistsScreen-এর মূল data
/// source। Non-autoDispose ইচ্ছাকৃতভাবে (favoritesProvider-এর একই
/// সিদ্ধান্ত অনুসরণ করে) — LibraryScreen-এর "Playlists" section এবং
/// full PlaylistsScreen দুই জায়গা থেকেই watch হতে পারে, বারবার screen
/// switch করলে stream পুনরায় তৈরি হওয়া এড়াতে।
final playlistsProvider = StreamProvider<List<PlaylistSummary>>((ref) {
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.watchPlaylists();
});

/// একটা নির্দিষ্ট playlist-এর পূর্ণ detail (metadata + ordered items) —
/// family provider, playlistId দিয়ে parameterized। PlaylistDetailScreen
/// এই provider watch করবে।
///
/// autoDispose ইচ্ছাকৃতভাবে ব্যবহার করা হচ্ছে (playlistsProvider থেকে
/// ভিন্ন) — একটা নির্দিষ্ট playlist-এর detail screen বন্ধ হয়ে গেলে সেই
/// stream subscription আর দরকার নেই, memory-তে ধরে রাখার প্রয়োজন নেই
/// (অনেকগুলো ভিন্ন playlist খোলা-বন্ধ করলে stale stream জমে থাকা এড়াতে)।
final playlistDetailProvider = StreamProvider.autoDispose
    .family<PlaylistDetail?, String>((ref, playlistId) {
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.watchPlaylistDetail(playlistId);
});