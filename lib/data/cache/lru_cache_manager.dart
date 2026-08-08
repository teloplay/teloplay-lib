import 'dart:async';

import '../../core/logging/app_logger.dart';

/// ⚠️ Phase 3 (Smart Cache) — Generic LRU (Least Recently Used) eviction
/// policy tracker।
///
/// এই ক্লাস নিজে কোনো ফাইল/bytes টাচ করে না — শুধু "কোন key কখন সবশেষ
/// access হয়েছে" আর "প্রতিটা entry-র আনুমানিক সাইজ কত" ট্র্যাক রাখে,
/// এবং cache-এর মোট সাইজ একটা budget ছাড়িয়ে গেলে কোন key(গুলো) evict
/// করা উচিত সেটা বলে দেয়। Actual eviction (ফাইল delete করা, DB row
/// আপডেট করা) caller-এর (`MediaAssetManager`) দায়িত্ব — এই সিদ্ধান্ত
/// ইচ্ছাকৃত, যাতে policy (কোনটা evict হবে) আর mechanism (কীভাবে delete
/// হবে) আলাদা থাকে, এবং ভবিষ্যতে policy বদলাতে চাইলে (যেমন LFU বা
/// hybrid) শুধু এই একটা ক্লাস বদলালেই চলবে।
///
/// Asset-agnostic — audio bytes cache এবং thumbnail bytes cache দুটোই
/// নিজেদের `LruCacheManager` instance রাখবে (আলাদা budget-এর কারণে,
/// দেখো `MediaAssetManager`), অথবা চাইলে একই instance-এ namespaced key
/// (যেমন `"audio:$videoId"` বনাম `"thumb:$videoId"`) দিয়ে একসাথেও রাখা
/// যায় — এই ক্লাস সেই সিদ্ধান্তের ব্যাপারে agnostic।
class LruCacheManager {
  final String label; // logging-এর জন্য (যেমন "audio", "thumbnail")
  final int maxSizeBytes;

  LruCacheManager({
    required this.label,
    required this.maxSizeBytes,
  });

  // key → সবশেষ access time। LinkedHashMap ব্যবহার করা হয়নি ইচ্ছাকৃতভাবে —
  // access order maintain করার বদলে explicit timestamp দিয়ে sort করা
  // হচ্ছে, কারণ এটা `MediaAssetManager`-এর সাথে সহজে সিরিয়ালাইজ/রিস্টোর
  // করা যায় (app restart-এর পরেও LRU history আংশিকভাবে বাঁচিয়ে রাখতে
  // চাইলে ভবিষ্যতে DB থেকে rebuild করা সহজ হবে)।
  final Map<String, DateTime> _lastAccessed = {};
  final Map<String, int> _sizeBytes = {};

  int _totalSizeBytes = 0;
  int get totalSizeBytes => _totalSizeBytes;

  int get entryCount => _sizeBytes.length;

  bool contains(String key) => _sizeBytes.containsKey(key);

  /// নতুন entry যোগ করা বা আগের entry-র access time রিফ্রেশ করা।
  void recordAccess(String key, {int? sizeBytes}) {
    final now = DateTime.now();
    _lastAccessed[key] = now;

    if (sizeBytes != null) {
      final previousSize = _sizeBytes[key] ?? 0;
      _sizeBytes[key] = sizeBytes;
      _totalSizeBytes += sizeBytes - previousSize;
    }
  }

  void remove(String key) {
    final size = _sizeBytes.remove(key);
    _lastAccessed.remove(key);
    if (size != null) {
      _totalSizeBytes -= size;
    }
  }

  void clear() {
    _lastAccessed.clear();
    _sizeBytes.clear();
    _totalSizeBytes = 0;
  }

  /// বর্তমান `totalSizeBytes` যদি `maxSizeBytes` ছাড়িয়ে যায়, তাহলে
  /// least-recently-used key গুলো একটা একটা করে বেছে নিয়ে ফেরত দেয়
  /// (oldest access-time আগে), যতক্ষণ না মোট সাইজ budget-এর নিচে নেমে
  /// আসে। এই মেথড নিজে কোনো state বদলায় না (`remove()` caller-কে
  /// আলাদাভাবে কল করতে হবে actual eviction সফল হওয়ার পরে) — যাতে যদি
  /// ফাইল-delete ব্যর্থ হয়, LRU state ভুলভাবে "clean" দেখানো না হয়।
  List<String> selectEvictionCandidates() {
    if (_totalSizeBytes <= maxSizeBytes) return [];

    final sortedKeys = _lastAccessed.keys.toList()
      ..sort((a, b) => _lastAccessed[a]!.compareTo(_lastAccessed[b]!));

    final candidates = <String>[];
    var projectedSize = _totalSizeBytes;

    for (final key in sortedKeys) {
      if (projectedSize <= maxSizeBytes) break;
      candidates.add(key);
      projectedSize -= _sizeBytes[key] ?? 0;
    }

    AppLogger.performance(
      '[cache/$label] eviction needed: total=${_mb(_totalSizeBytes)}MB '
      'budget=${_mb(maxSizeBytes)}MB → ${candidates.length} candidate(s)',
    );

    return candidates;
  }

  double _mb(int bytes) => bytes / (1024 * 1024);

  /// Debug/diagnostics — cache health verification-এর জন্য (roadmap:
  /// "Cache health verification")। কোনো side effect নেই।
  Map<String, Object> get debugSnapshot => {
        'label': label,
        'entryCount': entryCount,
        'totalSizeBytes': _totalSizeBytes,
        'maxSizeBytes': maxSizeBytes,
        'utilizationPercent':
            maxSizeBytes > 0 ? (_totalSizeBytes / maxSizeBytes * 100) : 0,
      };
}