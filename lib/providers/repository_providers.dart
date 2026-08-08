import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../services/behaviour_tracking_service.dart';
import 'database_provider.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LibraryRepository(db);
});

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PlaylistRepository(db);
});

// ⚠️ Phase 0.9 (Foundation Hardening) — BehaviourTrackingService এখানে
// provide করা হচ্ছে (এই ফাইলে, শুধু music-player-specific provider
// ফাইলে না) কারণ এটা shared/cross-cutting service — MusicPlayerRepository
// (play/skip/complete/search capture) ছাড়াও ভবিষ্যতে LibraryRepository
// (Phase 2, favorite-toggle capture) এই একই instance ব্যবহার করবে।
// database_provider.dart-এর appDatabaseProvider-এর উপর নির্ভরশীল, ঠিক
// উপরের দুটো repository provider-এর প্যাটার্ন অনুসরণ করে।
final behaviourTrackingServiceProvider =
    Provider<BehaviourTrackingService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return BehaviourTrackingService(db);
});