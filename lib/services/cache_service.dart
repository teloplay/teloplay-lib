import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/logging/app_logger.dart';
import '../data/cache/cache_manager.dart';
import '../data/cache/media_asset_manager.dart';
import '../data/repositories/cache_repository.dart';
import 'performance_service.dart';

/// ⚠️ Phase 3 (Smart Cache Engine) — Cache priority tier। এখন শুধু
/// দুইটা tier কার্যকর (`currentPlaying`, `preload`) — `frequentlyPlayed`
/// enum-এ থাকলেও `CacheService` এটা এখনো কোনো caller-এ পাঠায় না
/// (`CacheRepository.getFrequentlyPlayedVideoIds()` এখনো placeholder,
/// দেখো সেই ফাইলের নোট)। Enum-এ future tier আগে থেকে রাখা হয়েছে যাতে
/// পরে BehaviourTracking integration যোগ করার সময় priority-comparison
/// logic (`index` ভিত্তিক ordering — নিচে দেখো) নতুন করে ডিজাইন করা না
/// লাগে, শুধু নতুন caller যোগ করলেই চলবে।
enum CachePriority {
  /// এই মুহূর্তে যা বাজছে — সর্বোচ্চ priority, কখনো ইচ্ছাকৃতভাবে evict
  /// করা হয় না যতক্ষণ না track বদলায় (LRU natural aging ছাড়া)।
  currentPlaying,

  /// পরের ১-৩টা track (Adaptive Buffering/PreloadManager-এর প্যাটার্ন
  /// অনুসরণ করে) — background-এ preload হয়, current-এর চেয়ে কম priority।
  preload,

  /// ⚠️ RESERVED — Phase 7+ বা BehaviourTracking-driven bring-forward।
  /// এখনো কোনো caller এই priority ব্যবহার করে না।
  frequentlyPlayed,
}

/// ✅ Phase 3 Item D — `verifyCacheIntegrity()`-এর internal per-track
/// ফলাফল (checksum match/mismatch/lazily-populated) — শুধু
/// `CacheService`-এর ভেতরেই ব্যবহৃত, public API-তে exposed হয় না
/// (public API `CacheIntegrityReport`-এর aggregate counts পায়)।
enum _VerifyOutcome { ok, corrupted, checksumPopulated }

/// ✅ Phase 3 Item D — `verifyCacheIntegrity()`-এর aggregate ফলাফল।
/// Settings/Diagnostics screen এটা সরাসরি দেখাতে পারবে।
class CacheIntegrityReport {
  const CacheIntegrityReport({
    required this.totalChecked,
    required this.verifiedOk,
    required this.corrupted,
    required this.checksumsPopulated,
  });

  /// মোট কতগুলো cached track checked হয়েছে।
  final int totalChecked;

  /// checksum match করেছে (আগে থেকে populated ছিল)।
  final int verifiedOk;

  /// checksum mismatch বা file missing — evict + DB flag clear করা হয়েছে।
  final int corrupted;

  /// আগে checksum null ছিল, এই run-এ lazily populate করা হয়েছে (এখনো
  /// "corrupted" ধরা হয়নি, কারণ তুলনা করার মতো আগের checksum ছিল না)।
  final int checksumsPopulated;
}

/// ✅ Phase 3 Item D — `scanForOrphanFiles()`-এর ফলাফল — filesystem-এ
/// আছে কিন্তু DB-তে `cachedLocally=true` কোনো matching row নেই এমন
/// ফাইল (DB row delete/clear হয়ে গেছে কিন্তু filesystem cleanup miss
/// হয়েছিল, এমন orphan সরাতে)।
class OrphanScanReport {
  const OrphanScanReport({
    required this.orphanFilesFound,
    required this.bytesReclaimed,
  });

  /// যেসব orphan ফাইল পাওয়া গিয়ে delete করা হয়েছে (full path)।
  final List<String> orphanFilesFound;

  /// orphan ফাইল delete করে মোট কত byte ফেরত পাওয়া গেছে।
  final int bytesReclaimed;
}

/// ⚠️ Phase 3 (Smart Cache Engine) — সব cache orchestration logic-এর
/// single entry point। `MusicPlayerRepository` playback lifecycle
/// event (track শুরু, queue advance) এই service-কে জানাবে, এই service
/// সিদ্ধান্ত নেবে কী cache করতে হবে এবং কখন cleanup চালাতে হবে।
///
/// ✅ Phase 3 Item C (Thumbnail Cache Wiring) — audio cache orchestration
/// ছাড়াও এখন থাম্বনেইল cache-এর জন্য দুটো public method যোগ হয়েছে
/// (`checkCachedThumbnail`, `cacheThumbnailIfNeeded`) — `CachedArtwork`
/// widget এগুলো ব্যবহার করবে। এই দুটো method ইচ্ছাকৃতভাবে audio-র
/// `checkCachedFile`/`cacheTrack`-এর মতোই shape/naming-pattern অনুসরণ
/// করে (consistency, শেখার curve কম) কিন্তু আলাদা, কারণ:
///   - Low-RAM guard thumbnail-এ প্রযোজ্য না (thumbnail bytes ছোট,
///     audio download-এর মতো bandwidth/CPU-heavy না — Low-RAM mode
///     মানে RAM-সীমাবদ্ধতা, disk-cache একটা few-KB image লেখা কার্যত
///     negligible cost, আর thumbnail না থাকলে UI placeholder-এ পড়ে
///     যা user-experience-কে আরও খারাপ করে, তাই skip করার যুক্তি নেই)।
///   - `currentPlaying`-এর মতো priority guard thumbnail-এ নেই — কোনো
///     thumbnail কখনো "currently playing" অর্থে non-evictable না,
///     সবগুলোই সমান priority, শুধু LRU recency দিয়ে নিয়ন্ত্রিত।
///
/// ✅ Phase 3 Item D (Cache Health/Diagnostics) — এখন SHA-256 checksum
/// দিয়ে audio cache integrity verify করা যায় (`verifyCacheIntegrity`,
/// `verifySingleTrack`) এবং orphan filesystem entries scan+clean করা
/// যায় (`scanForOrphanFiles`)। checksum lazily populate হয় — প্রথমবার
/// verify-এর সময় null থাকলে হিসাব করে DB-তে বসানো হয়, mismatch তখনই
/// ধরা পড়ে যখন পরবর্তী কোনো verify-তে stored checksum আর file bytes
/// মেলে না।
class CacheService {
  final MediaAssetManager _assetManager;
  final CacheManager _cacheManager;
  final CacheRepository _cacheRepository;

  CacheService(
    this._assetManager,
    this._cacheManager,
    this._cacheRepository,
  );

  bool _initialized = false;
  bool _disposed = false;

  // ⚠️ FIX: initialize() সম্পূর্ণ হওয়া পর্যন্ত caller-রা (যেমন
  // CachedArtwork) এই Future await করতে পারবে, race condition এড়াতে।
  // Completer ব্যবহার করা হচ্ছে কারণ initialize() একাধিকবার কল হলেও
  // (idempotent guard আছে উপরেই) সবাই একই completion সিগন্যাল পাবে।
  final Completer<void> _readyCompleter = Completer<void>();

  /// App-startup-এর পরে যেকোনো সময় await করা যায় — CacheService
  /// initialize() শেষ না হওয়া পর্যন্ত suspend থাকবে, শেষ হলে সাথে সাথে
  /// resolve হবে। ইতিমধ্যে initialized থাকলে সাথে সাথেই resolve হবে
  /// (Completer একবার complete হলে future বারবার await করা নিরাপদ)।
  Future<void> get ready => _readyCompleter.future;

  bool get isInitialized => _initialized;

  // ⚠️ current track-এর videoId আলাদাভাবে ট্র্যাক রাখা হচ্ছে যাতে
  // eviction sweep কখনো ভুলবশত এই মুহূর্তে বাজতে-থাকা track-কে evict
  // candidate হিসেবে বেছে না নেয় (দেখো `_runEvictionSweep`-এর guard)।
  // ⚠️ এই guard শুধু audio-র জন্য প্রযোজ্য — thumbnail eviction
  // (`_runThumbnailEvictionSweep`) এই guard ব্যবহার করে না, উপরের
  // class-doc দেখো কেন।
  String? _currentPlayingVideoId;

  /// App-startup-এ একবার কল করতে হবে — `MediaAssetManager.initialize()`
  /// এবং DB↔filesystem reconciliation করে (orphan detection: DB-তে
  /// `cachedLocally=true` কিন্তু ফাইল নেই, বা উল্টো — কোনোটাই crash-worthy
  /// না, শুধু log + DB flag correction)।
  Future<void> initialize() async {
    if (_initialized) return;
    await _assetManager.initialize();
    await _reconcileWithFilesystem();
    _initialized = true;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    AppLogger.performance('[cache-service] initialized');
  }

  /// Cache health verification (roadmap: "Cache health verification",
  /// "Corrupted cache auto-remove") — DB-তে cached বলে মার্ক করা প্রতিটা
  /// track-এর জন্য ফাইল সত্যিই আছে কিনা যাচাই করা, না থাকলে DB flag
  /// clear করে দেওয়া (orphan DB entry)।
  ///
  /// ⚠️ Item C নোট: এই reconciliation এখনো শুধু audio টেবিলের উপর কাজ
  /// করে (`CacheRepository.getAllCachedSongs()`), thumbnail-এর জন্য
  /// এখনো কোনো Drift-backed persistence/reconciliation নেই। এটা
  /// ইচ্ছাকৃত scope-সীমা — thumbnail cache এখন শুধু filesystem+in-memory
  /// LRU-নির্ভর (Drift row নেই, `Songs.thumbnailCachedLocally`-জাতীয়
  /// কোনো column নেই), তাই app restart-এর পরে thumbnail LRU access-history
  /// খালি শুরু হয় (audio-র মতো DB থেকে rebuild হয় না)। প্রভাব সীমিত:
  /// প্রথম কয়েকটা thumbnail access-এ LRU recency তথ্য পুরনো/অনুপস্থিত
  /// থাকবে, কিন্তু ফাইল filesystem-এ থাকলে cache hit ঠিকই কাজ করবে
  /// (`MediaAssetManager.get()` filesystem-stat করে, DB-নির্ভর না)। এটা
  /// Phase 3 D (Cache Health/Diagnostics) স্কোপে পূর্ণাঙ্গ করা হবে যদি
  /// দরকার মনে হয়, এখনই না (over-engineering এড়াতে)।
  Future<void> _reconcileWithFilesystem() async {
    try {
      final cachedSongs = await _cacheRepository.getAllCachedSongs();
      var orphanCount = 0;

      for (final song in cachedSongs) {
        final result = await _cacheManager.checkCache(song.videoId);
        if (!result.isHit) {
          // DB বলছে cached, filesystem বলছে নেই — orphan DB flag।
          await _cacheRepository.clearCacheFlag(song.videoId);
          orphanCount++;
        } else {
          // ফাইল আছে — LRU tracker-কে জানানো (app restart-এর পরে
          // in-memory LRU state খালি থাকে, DB থেকে rebuild করা হচ্ছে)।
          _assetManager
              .lruFor(MediaAssetType.audio)
              .recordAccess(song.videoId, sizeBytes: song.sizeBytes);
        }
      }

      if (orphanCount > 0) {
        AppLogger.performance(
          '[cache-service] reconciliation: $orphanCount orphan DB flag(s) cleared',
        );
      }
    } catch (e) {
      AppLogger.error('CacheService._reconcileWithFilesystem failed', e);
    }
  }

  /// দ্রুত cache-hit check — শুধু local file path (থাকলে) রিটার্ন করে,
  /// LRU access time refresh করে (দেখো `CacheManager.checkCache` →
  /// `MediaAssetManager.get`)। `MusicPlayerRepository.playVideoId()`
  /// এটা network resolve শুরু করার *আগে* কল করে — hit হলে resolve
  /// সম্পূর্ণ এড়ানো যায়।
  ///
  /// non-throwing — `_initialized` false থাকলে বা lookup ব্যর্থ হলে
  /// null রিটার্ন করে (caller স্বাভাবিক resolve path-এ চলে যায়)।
  Future<String?> checkCachedFile(String videoId) async {
    if (!_initialized) return null;
    final result = await _cacheManager.checkCache(videoId);
    return result.isHit ? result.localFilePath : null;
  }

  /// ✅ Phase 3 Item C — দ্রুত thumbnail cache-hit check। `CachedArtwork`
  /// build সময় এটা কল করবে — hit হলে সরাসরি local file দেখানো যাবে,
  /// miss হলে placeholder + background fetch শুরু হবে
  /// (`cacheThumbnailIfNeeded()`)।
  ///
  /// non-throwing — miss/uninitialized হলে null।
  Future<String?> checkCachedThumbnail(String videoId) async {
    if (!_initialized) return null;
    final result = await _cacheManager.checkThumbnailCache(videoId);
    return result.isHit ? result.localFilePath : null;
  }

  /// ✅ Phase 3 Item C — thumbnail cache করা (miss হলে download+save)।
  /// `CachedArtwork` widget UI build-flow-এর ভেতর থেকে fire-and-forget
  /// কল করবে (await না করে) — thumbnail caching কখনো UI render ব্লক
  /// করা উচিত না, cache হয়ে গেলে widget নিজে থেকে rebuild ট্রিগার করবে
  /// caller-এর state-management দিয়ে।
  ///
  /// রিটার্ন করে local file path (সফল হলে) বা null (ব্যর্থ/skip হলে) —
  /// caller চাইলে awaited ব্যবহারও করতে পারে (যেমন প্রথম-লোড সময়
  /// synchronous দেখাতে চাইলে), তাই deliberately non-void।
  Future<String?> cacheThumbnailIfNeeded({
    required String videoId,
    required String imageUrl,
  }) async {
    if (!_initialized) return null;

    final outcome = await _cacheManager.cacheThumbnail(
      videoId: videoId,
      imageUrl: imageUrl,
    );

    if (!outcome.result.isHit || outcome.result.localFilePath == null) {
      return null;
    }

    if (outcome.evictionCandidates.isNotEmpty) {
      await _runThumbnailEvictionSweep(outcome.evictionCandidates);
    }

    return outcome.result.localFilePath;
  }

  /// ✅ Phase 3 Item C — thumbnail LRU eviction candidates থেকে actual
  /// removal। Audio-র `_runEvictionSweep`-এর সমান্তরাল, কিন্তু
  /// `_currentPlayingVideoId` guard নেই (class-doc-এ ব্যাখ্যা দেখো —
  /// thumbnail-এর কোনো non-evictable priority tier নেই)।
  Future<void> _runThumbnailEvictionSweep(List<String> candidates) async {
    for (final videoId in candidates) {
      await _assetManager.evict(MediaAssetType.thumbnail, videoId);
      // ⚠️ কোনো `_cacheRepository.clearCacheFlag()` কল নেই এখানে —
      // thumbnail-এর জন্য এখনো কোনো DB-backed cached-flag নেই (উপরের
      // `_reconcileWithFilesystem()`-এর নোট দেখো), তাই evict শুধু
      // filesystem + in-memory LRU state-এই সীমাবদ্ধ।
    }

    AppLogger.performance(
      '[cache-service] thumbnail eviction sweep complete: '
      '${candidates.length} candidate(s) processed',
    );
  }

  /// Current track cache করা — playback শুরু হওয়ার পরে
  /// `MusicPlayerRepository` থেকে fire-and-forget কল হবে।
  Future<void> cacheTrack({
    required String videoId,
    required String streamUrl,
    required CachePriority priority,
  }) async {
    if (!_initialized) return;

    // ⚠️ Smart Performance — low RAM mode-এ cache download একটা
    // non-critical, network/CPU/disk-খরচকারী কাজ, তাই স্কিপ করা হয়।
    if (PerformanceService.instance.isLowRamMode) {
      AppLogger.performance(
        '[cache-service] cacheTrack skipped — low RAM mode ($videoId)',
      );
      return;
    }

    if (priority == CachePriority.currentPlaying) {
      _currentPlayingVideoId = videoId;
    }

    final alreadyCached = await _cacheManager.checkCache(videoId);
    if (alreadyCached.isHit) {
      return;
    }

    await PerformanceService.instance.runThrottled(
      'cache-track:$videoId',
      () async {
        final outcome = await _cacheManager.cacheAudio(
          videoId: videoId,
          streamUrl: streamUrl,
        );

        if (!outcome.result.isHit || outcome.result.localFilePath == null) {
          return;
        }

        int actualSizeBytes;
        try {
          actualSizeBytes =
              await File(outcome.result.localFilePath!).length();
        } catch (e) {
          AppLogger.error(
            'CacheService: file size read failed ($videoId)',
            e,
          );
          return;
        }

        await _cacheRepository.markCached(
          videoId: videoId,
          cachePath: outcome.result.localFilePath!,
          cacheSizeBytes: actualSizeBytes,
        );

        AppLogger.performance(
          '[cache-service] cached: $videoId priority=$priority',
        );

        if (outcome.evictionCandidates.isNotEmpty) {
          await _runEvictionSweep(outcome.evictionCandidates);
        }
      },
    );
  }

  /// একাধিক track-কে preload-priority দিয়ে cache করা।
  Future<void> preloadUpcoming(
    List<({String videoId, String streamUrl})> tracks,
  ) async {
    if (!_initialized) return;
    if (PerformanceService.instance.isLowRamMode) {
      AppLogger.performance(
        '[cache-service] preloadUpcoming skipped — low RAM mode',
      );
      return;
    }

    for (final track in tracks) {
      if (_disposed) return;
      await cacheTrack(
        videoId: track.videoId,
        streamUrl: track.streamUrl,
        priority: CachePriority.preload,
      );
    }
  }

  /// LRU-নির্বাচিত audio candidates evict করা — filesystem delete +
  /// `MediaAssetManager`-এর in-memory LRU state clear + DB flag clear।
  Future<void> _runEvictionSweep(List<String> candidates) async {
    for (final videoId in candidates) {
      if (videoId == _currentPlayingVideoId) {
        AppLogger.performance(
          '[cache-service] eviction skip (currently playing): $videoId',
        );
        continue;
      }

      await _assetManager.evict(MediaAssetType.audio, videoId);
      await _cacheRepository.clearCacheFlag(videoId);
    }

    AppLogger.performance(
      '[cache-service] eviction sweep complete: ${candidates.length} candidate(s) processed',
    );
  }

  /// User-initiated "Clear All Cache" — Settings screen থেকে কল হবে।
  Future<void> clearAllCache() async {
    if (!_initialized) return;

    final cachedSongs = await _cacheRepository.getAllCachedSongs();

    await _assetManager.clearAll(MediaAssetType.audio);

    for (final song in cachedSongs) {
      await _cacheRepository.clearCacheFlag(song.videoId);
    }

    AppLogger.performance(
      '[cache-service] clearAllCache: ${cachedSongs.length} track(s) cleared',
    );
  }

  /// ✅ Phase 3 Item C — User-initiated "Clear Thumbnail Cache" (ভবিষ্যতে
  /// Settings screen-এ আলাদা toggle হিসেবে থাকতে পারে audio থেকে, কারণ
  /// thumbnail budget (50MB) audio budget (500MB) থেকে independent)।
  Future<void> clearAllThumbnailCache() async {
    if (!_initialized) return;
    await _assetManager.clearAll(MediaAssetType.thumbnail);
    AppLogger.performance('[cache-service] clearAllThumbnailCache done');
  }

  /// User-initiated single-track delete — Library-র "Downloaded Songs"
  /// section-এ প্রতিটা entry-র delete button থেকে কল হবে।
  Future<bool> evictTrack(String videoId) async {
    if (!_initialized) return false;

    if (videoId == _currentPlayingVideoId) {
      AppLogger.performance(
        '[cache-service] evictTrack skip (currently playing): $videoId',
      );
      return false;
    }

    await _assetManager.evict(MediaAssetType.audio, videoId);
    await _cacheRepository.clearCacheFlag(videoId);

    AppLogger.performance('[cache-service] evictTrack: $videoId');
    return true;
  }

  /// Settings screen-এর "cache size" slider/dropdown থেকে কল হবে
  /// (200MB/500MB/1GB/Unlimited)।
  Future<void> updateAudioCacheBudget(int newMaxSizeBytes) async {
    _assetManager.updateBudget(MediaAssetType.audio, newMaxSizeBytes);
    await _reconcileWithFilesystem();

    final candidates =
        _assetManager.lruFor(MediaAssetType.audio).selectEvictionCandidates();
    if (candidates.isNotEmpty) {
      await _runEvictionSweep(candidates);
    }

    AppLogger.performance(
      '[cache-service] audio cache budget updated: '
      '${(newMaxSizeBytes / (1024 * 1024)).toStringAsFixed(0)}MB',
    );
  }

  /// ✅ Phase 3 Item C — thumbnail cache budget বদলানো। Audio-র
  /// `updateAudioCacheBudget()`-এর সমান্তরাল, কিন্তু `_reconcileWithFilesystem()`
  /// কল করে না (সেটা এখনো audio-only, উপরের নোট দেখো) — শুধু নতুন
  /// budget বসিয়ে সাথে সাথে eviction candidates চেক করে।
  Future<void> updateThumbnailCacheBudget(int newMaxSizeBytes) async {
    _assetManager.updateBudget(MediaAssetType.thumbnail, newMaxSizeBytes);

    final candidates = _assetManager
        .lruFor(MediaAssetType.thumbnail)
        .selectEvictionCandidates();
    if (candidates.isNotEmpty) {
      await _runThumbnailEvictionSweep(candidates);
    }

    AppLogger.performance(
      '[cache-service] thumbnail cache budget updated: '
      '${(newMaxSizeBytes / (1024 * 1024)).toStringAsFixed(0)}MB',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ✅ Phase 3 Item D — Cache Health/Diagnostics (RESTORED)
  // ═══════════════════════════════════════════════════════════

  /// DB-তে `cachedLocally=true` মার্ক করা প্রতিটা audio track-এর SHA-256
  /// checksum verify করা — corrupted (mismatch/missing-file) পাওয়া গেলে
  /// evict + DB flag clear, checksum না থাকলে (প্রথমবার) lazily populate।
  /// Settings/Diagnostics screen-এ "Verify Cache" বাটন থেকে কল হবে
  /// (ব্যয়বহুল — পুরো cached library পড়তে হয়, তাই user-initiated,
  /// automatic schedule-এ না)।
  Future<CacheIntegrityReport> verifyCacheIntegrity() async {
    if (!_initialized) {
      return const CacheIntegrityReport(
        totalChecked: 0,
        verifiedOk: 0,
        corrupted: 0,
        checksumsPopulated: 0,
      );
    }

    final cachedSongs = await _cacheRepository.getAllCachedSongs();
    var verifiedOk = 0;
    var corrupted = 0;
    var checksumsPopulated = 0;

    for (final song in cachedSongs) {
      if (_disposed) break;
      final outcome = await _verifySingleTrackInternal(song);
      switch (outcome) {
        case _VerifyOutcome.ok:
          verifiedOk++;
        case _VerifyOutcome.corrupted:
          corrupted++;
        case _VerifyOutcome.checksumPopulated:
          checksumsPopulated++;
      }
    }

    AppLogger.performance(
      '[cache-service] verifyCacheIntegrity: '
      'checked=${cachedSongs.length} ok=$verifiedOk '
      'corrupted=$corrupted populated=$checksumsPopulated',
    );

    return CacheIntegrityReport(
      totalChecked: cachedSongs.length,
      verifiedOk: verifiedOk,
      corrupted: corrupted,
      checksumsPopulated: checksumsPopulated,
    );
  }

  /// একটা নির্দিষ্ট track-এর জন্য একক verify — পুরো library scan না করে
  /// (যেমন playback শুরু হওয়ার ঠিক আগে quick-sanity check)।
  ///
  /// রিটার্ন করে `true` যদি ok/lazily-populated হয়, `false` যদি
  /// corrupted (evict হয়ে গেছে) বা track cached না থাকে।
  Future<bool> verifySingleTrack(String videoId) async {
    if (!_initialized) return false;

    final song = await _cacheRepository.getCachedSong(videoId);
    if (song == null) return false;

    final outcome = await _verifySingleTrackInternal(song);
    return outcome != _VerifyOutcome.corrupted;
  }

  Future<_VerifyOutcome> _verifySingleTrackInternal(
    ({String videoId, String cachePath, int sizeBytes, String? cacheChecksum}) song,
  ) async {
    final file = File(song.cachePath);
    if (!await file.exists()) {
      await _cacheRepository.clearCacheFlag(song.videoId);
      return _VerifyOutcome.corrupted;
    }

    try {
      final bytes = await file.readAsBytes();
      final actualChecksum = sha256.convert(bytes).toString();

      if (song.cacheChecksum == null) {
        await _cacheRepository.setChecksum(song.videoId, actualChecksum);
        return _VerifyOutcome.checksumPopulated;
      }

      if (song.cacheChecksum != actualChecksum) {
        await _assetManager.evict(MediaAssetType.audio, song.videoId);
        await _cacheRepository.clearCacheFlag(song.videoId);
        AppLogger.performance(
          '[cache-service] corrupted (checksum mismatch): ${song.videoId}',
        );
        return _VerifyOutcome.corrupted;
      }

      return _VerifyOutcome.ok;
    } catch (e) {
      AppLogger.error(
        'CacheService._verifySingleTrackInternal failed (${song.videoId})',
        e,
      );
      return _VerifyOutcome.corrupted;
    }
  }

  /// Audio cache directory-তে filesystem scan করে এমন ফাইল খুঁজে বের
  /// করা যেগুলোর কোনো matching `cachedLocally=true` DB row নেই (DB flag
  /// clear হয়ে গেছে কিন্তু filesystem delete miss হয়েছিল, বা অন্য কোনো
  /// bug-এর কারণে orphan file তৈরি হয়েছে) — পাওয়া মাত্র delete করে
  /// দেওয়া হয়।
  Future<OrphanScanReport> scanForOrphanFiles() async {
    if (!_initialized) {
      return const OrphanScanReport(orphanFilesFound: [], bytesReclaimed: 0);
    }

    final cachedVideoIds = await _cacheRepository.getCachedVideoIdSet();
    final orphanPaths = <String>[];
    var bytesReclaimed = 0;

    final dir = Directory(_assetManager.directoryFor(MediaAssetType.audio));
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final videoId = _extractVideoIdFromPath(entity.path);
        if (videoId == null || !cachedVideoIds.contains(videoId)) {
          try {
            final size = await entity.length();
            await entity.delete();
            orphanPaths.add(entity.path);
            bytesReclaimed += size;
          } catch (e) {
            AppLogger.error(
              'CacheService.scanForOrphanFiles delete failed (${entity.path})',
              e,
            );
          }
        }
      }
    }

    AppLogger.performance(
      '[cache-service] scanForOrphanFiles: '
      'found=${orphanPaths.length} reclaimed=${bytesReclaimed}B',
    );

    return OrphanScanReport(
      orphanFilesFound: orphanPaths,
      bytesReclaimed: bytesReclaimed,
    );
  }

  String? _extractVideoIdFromPath(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName.isEmpty ? null : fileName;
    return fileName.substring(0, dotIndex);
  }

  /// Diagnostics — Settings screen-এ "Storage used: X MB / Y MB" দেখানোর
  /// জন্য।
  Map<String, Object> get debugSnapshot => _assetManager.debugSnapshot;

  void dispose() {
    _disposed = true;
    _cacheManager.dispose();
  }
}