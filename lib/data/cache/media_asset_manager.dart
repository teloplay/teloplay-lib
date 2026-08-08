import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import 'lru_cache_manager.dart';

/// ⚠️ Phase 3 (Smart Cache) — কোন ধরনের asset, generic disk-cache
/// layer-এর জন্য শুধু namespacing/subfolder নির্ধারণ করতে ব্যবহার হয়।
///
/// Roadmap নীতি ("Media Asset Cache Foundation"): "Cache layer শুধু
/// audio ধরে ডিজাইন করা হবে না, generic Media Asset Cache হিসেবে তৈরি
/// হবে... ভবিষ্যতে একই architecture ব্যবহার করবে: Audio cache, Album
/// art cache, Canvas/Short Video cache (Phase 7+), Lyrics cache,
/// Thumbnail cache"।
///
/// নতুন asset type যোগ করতে এই enum-এ একটা মান বাড়ালেই যথেষ্ট —
/// `MediaAssetManager`/`LruCacheManager`-এর কোনো rewrite লাগে না
/// (constructor-এ প্রতিটা type-এর নিজস্ব budget/subfolder pass করা
/// হয়)।
enum MediaAssetType {
  audio,
  thumbnail,
  // lyrics,  // Phase 7+ — placeholder, এখনই enum-এ যোগ করা হয়নি কারণ
  // ব্যবহার শুরু না হওয়া পর্যন্ত dead enum value রাখা roadmap-এর
  // "over-engineering এড়ানো" নীতির বিরুদ্ধে যায়। যোগ করা এক লাইনের কাজ।
}

extension on MediaAssetType {
  /// Disk-এ subfolder নাম (cache root-এর নিচে)।
  String get subfolder => switch (this) {
        MediaAssetType.audio => 'audio',
        MediaAssetType.thumbnail => 'thumbnail',
      };

  String get label => switch (this) {
        MediaAssetType.audio => 'audio',
        MediaAssetType.thumbnail => 'thumbnail',
      };
}

/// একটা cached asset-এর ফলাফল — hit হলে local file path, miss হলে null।
class CachedAssetResult {
  final String key;
  final MediaAssetType type;
  final File? file;
  final bool isHit;

  const CachedAssetResult({
    required this.key,
    required this.type,
    this.file,
    required this.isHit,
  });

  static CachedAssetResult miss(String key, MediaAssetType type) =>
      CachedAssetResult(key: key, type: type, isHit: false);
}

/// ⚠️ Phase 3 (Smart Cache) — Generic Media Asset Cache।
///
/// এই ক্লাস filesystem-এ raw bytes read/write করে এবং `LruCacheManager`
/// (policy) + Drift-backed persistence (`CacheRepository`, পরের ব্যাচে
/// আসবে) এর মধ্যে সেতু হিসেবে কাজ করে। `MediaAssetManager` নিজে Drift
/// টাচ করে না (dependency injection-এর মাধ্যমে persistence callback
/// নেয়) — এই সিদ্ধান্ত ইচ্ছাকৃত, যাতে filesystem-mechanics আর
/// DB-bookkeeping আলাদা থাকে এবং future asset type (lyrics — টেক্সট,
/// ফাইল না) চাইলে filesystem অংশ পুরোপুরি bypass করে শুধু DB persistence
/// reuse করতে পারে।
///
/// প্রতিটা `MediaAssetType`-এর নিজস্ব `LruCacheManager` (আলাদা budget,
/// কারণ audio bytes সাধারণত thumbnail-এর চেয়ে বহুগুণ বড় — একই budget
/// শেয়ার করলে thumbnail cache প্রায়ই audio-এর চাপে evict হয়ে যেত)।
class MediaAssetManager {
  final Map<MediaAssetType, LruCacheManager> _lruManagers;
  Directory? _cacheRootDir;

  /// [audioMaxSizeBytes]/[thumbnailMaxSizeBytes] — user-configurable
  /// (Settings-এর মাধ্যমে, দেখো `CacheService` পরের ব্যাচে) — এখানে শুধু
  /// default প্রাথমিক মান, caller পরে `updateBudget()` দিয়ে বদলাতে পারবে।
  MediaAssetManager({
    required int audioMaxSizeBytes,
    required int thumbnailMaxSizeBytes,
  }) : _lruManagers = {
          MediaAssetType.audio: LruCacheManager(
            label: MediaAssetType.audio.label,
            maxSizeBytes: audioMaxSizeBytes,
          ),
          MediaAssetType.thumbnail: LruCacheManager(
            label: MediaAssetType.thumbnail.label,
            maxSizeBytes: thumbnailMaxSizeBytes,
          ),
        };

  bool _initialized = false;

  /// App-startup-এ একবার কল করতে হবে — cache root directory তৈরি/নিশ্চিত
  /// করে, প্রতিটা asset-type subfolder বানায়। এই মেথড filesystem-কে
  /// LRU state-এর সাথে sync করে না (সেটা `CacheService.warmUpFromDb()`-এর
  /// দায়িত্ব, পরের ব্যাচে) — এখানে শুধু directory structure নিশ্চিত করা
  /// হয়।
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      _cacheRootDir = Directory(p.join(appSupportDir.path, 'media_cache'));
      await _cacheRootDir!.create(recursive: true);

      for (final type in MediaAssetType.values) {
        await _subfolderDir(type).create(recursive: true);
      }

      _initialized = true;
      AppLogger.performance(
        '[media-asset-cache] initialized at ${_cacheRootDir!.path}',
      );
    } catch (e) {
      AppLogger.error('MediaAssetManager.initialize failed', e);
      // ⚠️ non-fatal — cache init ব্যর্থ হলেও app চলা উচিত, শুধু cache
      // hit না হয়ে সবসময় network/re-resolve fallback হবে (Smart Cache
      // একটা optimization, correctness-critical path না)।
    }
  }

  Directory _subfolderDir(MediaAssetType type) {
    final root = _cacheRootDir;
    if (root == null) {
      throw StateError(
        'MediaAssetManager: initialize() কল করা হয়নি এখনো',
      );
    }
    return Directory(p.join(root.path, type.subfolder));
  }

  /// ✅ Phase 3 Item D — public getter, `_subfolderDir()`-এর wrapper।
  /// `CacheService.scanForOrphanFiles()`-এর orphan-file scan-এর জন্য
  /// দরকার (filesystem directory সরাসরি list করতে হবে বাইরের থেকে)।
  /// আগে `_subfolderDir()` private ছিল, orphan-scan feature আসার আগে
  /// বাইরের কোনো caller-এর directory path দরকার ছিল না।
  String directoryFor(MediaAssetType type) => _subfolderDir(type).path;

  /// [key]-এর জন্য cached file path বানানো (extension caller দেয়, যেমন
  /// audio-এর জন্য কোনো নির্দিষ্ট extension নাও থাকতে পারে stream URL
  /// থেকে বলে সবসময় খালি রাখা যায়, thumbnail-এর জন্য সাধারণত `.jpg`)।
  File _fileFor(MediaAssetType type, String key, {String extension = ''}) {
    // ⚠️ Key sanitization — videoId সাধারণত filesystem-safe (alphanumeric
    // + `-`/`_`), কিন্তু defensive হিসেবে path separator বা অন্য বিপজ্জনক
    // char থাকলে sanitize করা হচ্ছে, যাতে filesystem escape/collision না
    // হয়।
    final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final fileName = extension.isEmpty ? safeKey : '$safeKey$extension';
    return File(p.join(_subfolderDir(type).path, fileName));
  }

  /// Cache lookup — file exist করলে LRU access time রিফ্রেশ করে hit
  /// রিটার্ন করে, না থাকলে miss।
  Future<CachedAssetResult> get(
    MediaAssetType type,
    String key, {
    String extension = '',
  }) async {
    if (!_initialized) return CachedAssetResult.miss(key, type);

    try {
      final file = _fileFor(type, key, extension: extension);
      if (!await file.exists()) {
        return CachedAssetResult.miss(key, type);
      }

      _lruManagers[type]!.recordAccess(key);
      return CachedAssetResult(
        key: key,
        type: type,
        file: file,
        isHit: true,
      );
    } catch (e) {
      AppLogger.error('MediaAssetManager.get failed (key=$key)', e);
      return CachedAssetResult.miss(key, type);
    }
  }

  /// নতুন asset bytes লিখে cache-এ রাখা। Write সফল হলে LRU-তে size-সহ
  /// entry record হয় এবং eviction candidate list রিটার্ন করা হয় (যদি
  /// এই write-এর ফলে budget ছাড়িয়ে যায়) — caller (`CacheService`)
  /// এই candidates নিয়ে `evict()` কল করবে DB row cleanup-সহ।
  ///
  /// non-throwing — write ব্যর্থ হলে শুধু log করে null রিটার্ন করে,
  /// exception propagate করে না (caching একটা optimization, playback/
  /// UI flow-কে ব্লক করা উচিত না)।
  Future<({File file, List<String> evictionCandidates})?> put(
    MediaAssetType type,
    String key,
    List<int> bytes, {
    String extension = '',
  }) async {
    if (!_initialized) return null;

    try {
      final file = _fileFor(type, key, extension: extension);
      await file.writeAsBytes(bytes, flush: true);

      final lru = _lruManagers[type]!;
      lru.recordAccess(key, sizeBytes: bytes.length);

      AppLogger.performance(
        '[media-asset-cache/${type.label}] stored key=$key '
        'size=${(bytes.length / 1024).toStringAsFixed(1)}KB',
      );

      return (file: file, evictionCandidates: lru.selectEvictionCandidates());
    } catch (e) {
      AppLogger.error('MediaAssetManager.put failed (key=$key)', e);
      return null;
    }
  }

  /// একটা নির্দিষ্ট key evict করা — file delete + LRU state থেকে remove।
  /// `LruCacheManager.selectEvictionCandidates()` শুধু candidate বাছাই
  /// করে, actual removal এই মেথড করে (দেখো `LruCacheManager`-এর
  /// class-doc — policy vs mechanism বিভাজন)।
  Future<void> evict(MediaAssetType type, String key) async {
    try {
      final file = _fileFor(type, key);
      if (await file.exists()) {
        await file.delete();
      }
      _lruManagers[type]!.remove(key);
      AppLogger.performance('[media-asset-cache/${type.label}] evicted key=$key');
    } catch (e) {
      AppLogger.error('MediaAssetManager.evict failed (key=$key)', e);
    }
  }

  /// একটা asset type-এর পুরো cache খালি করা (LRU state + disk ফাইল সব)।
  /// User manual "clear cache" action বা corrupted-cache-এর ব্যাপক
  /// cleanup-এর জন্য।
  Future<void> clearAll(MediaAssetType type) async {
    try {
      final dir = _subfolderDir(type);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      _lruManagers[type]!.clear();
      AppLogger.performance('[media-asset-cache/${type.label}] cleared all');
    } catch (e) {
      AppLogger.error('MediaAssetManager.clearAll failed (type=$type)', e);
    }
  }

  /// User-configurable cache size বদলানো হলে (Settings screen থেকে) কল
  /// হবে — নতুন budget কার্যকর হয়, প্রয়োজনে caller পরে eviction sweep
  /// trigger করবে (এই মেথড নিজে eviction করে না, শুধু budget আপডেট)।
  ///
  /// ⚠️ এই মেথড ইচ্ছাকৃতভাবে বিদ্যমান LRU access-history in-memory copy
  /// করে না — নতুন, খালি `LruCacheManager` বসানো হয় শুধু নতুন
  /// `maxSizeBytes` দিয়ে। budget কমানোর ঠিক পরের মুহূর্তে
  /// `selectEvictionCandidates()` fresh entry না থাকায় কিছু রিটার্ন
  /// করবে না, যতক্ষণ না assets আবার access হয় বা caller
  /// `CacheService.warmUpFromDb()` (source of truth Drift থেকে rebuild,
  /// পরের ব্যাচে) আবার চালায়। এটা নিরাপদ trade-off: ভুল/stale in-memory
  /// state দিয়ে ভুল file evict করার চেয়ে সাময়িকভাবে eviction স্কিপ হওয়া
  /// ভালো — caller-এর দায়িত্ব budget বদলানোর পরে `warmUpFromDb()` কল
  /// করা, যাতে real state থেকে LRU ঠিকভাবে rebuild হয়।
  void updateBudget(MediaAssetType type, int newMaxSizeBytes) {
    final old = _lruManagers[type]!;
    _lruManagers[type] =
        LruCacheManager(label: old.label, maxSizeBytes: newMaxSizeBytes);
  }

  LruCacheManager lruFor(MediaAssetType type) => _lruManagers[type]!;

  /// Diagnostics — Cache Health Monitor (roadmap Phase 3/7+) এই স্ন্যাপশট
  /// ব্যবহার করবে।
  Map<String, Object> get debugSnapshot => {
        for (final entry in _lruManagers.entries)
          entry.key.label: entry.value.debugSnapshot,
      };
}