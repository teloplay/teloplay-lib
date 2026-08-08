import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cache/cache_manager.dart';
import '../data/cache/media_asset_manager.dart';
import '../data/repositories/cache_repository.dart';
import '../services/cache_service.dart';
import 'database_provider.dart';

// ⚠️ Phase 3 (Smart Cache) — CacheService provider।
//
// `playbackEngineProvider`-এর ঠিক পাশেই একই কনভেনশনে (plain
// `Provider<T>`, Riverpod v3 legacy-style API) রাখা হলো।
//
// `database_provider.dart`-এর `appDatabaseProvider` কনফার্মড — এটাই
// পুরো app-এ একমাত্র `AppDatabase` singleton source (QueueRepository/
// SettingsRepository একইভাবে এটা ব্যবহার করে), তাই এখানে নতুন
// `AppDatabase()` না বানিয়ে সেই একই instance reuse করা হচ্ছে।
final cacheServiceProvider = Provider<CacheService>((ref) {
  final db = ref.watch(appDatabaseProvider);

  // ⚠️ Default budgets — audio 500MB (roadmap-এর কনফার্মড ডিফল্ট),
  // thumbnail 50MB (audio-এর তুলনায় ছোট, কিন্তু সংখ্যায় বেশি track-এর
  // thumbnail ধরে রাখা সম্ভব হয় এই আকারে)। User Settings থেকে audio
  // budget বদলালে `CacheService.updateAudioCacheBudget()` কল হবে
  // (Settings UI ব্যাচে wire হবে) — provider পুনরায় তৈরি হয় না, একই
  // instance-এর ভেতরের budget বদলায়।
  final mediaAssetManager = MediaAssetManager(
    audioMaxSizeBytes: 500 * 1024 * 1024,
    thumbnailMaxSizeBytes: 50 * 1024 * 1024,
  );

  final cacheManager = CacheManager(mediaAssetManager);
  final cacheRepository = CacheRepository(db);

  final service =
      CacheService(mediaAssetManager, cacheManager, cacheRepository);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});