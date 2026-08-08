/// একটা raw History log entry — প্রতিটা play event আলাদা row হিসেবে
/// (timestamp সহ), chronological History screen-এ দেখানোর জন্য।
///
/// এটা "Recently Played" থেকে ইচ্ছাকৃতভাবে আলাদা model। History raw
/// log (একই গান একাধিকবার আলাদা row-এ, প্রতিটা play আলাদা event),
/// কিন্তু Recently Played distinct/grouped (একই গান একবার, সর্বশেষ
/// play-timestamp অনুযায়ী) — দুটো ভিন্ন ধারণা, তাই দুটো আলাদা model +
/// আলাদা query method (দেখো library_repository.dart)।
class HistoryLogEntry {
  /// HistoryEntries.id (UUID) — per-entry delete-এর জন্য দরকার, কারণ
  /// একই songId-র একাধিক row থাকতে পারে (songId দিয়ে delete করলে সব
  /// instance মুছে যেত, ভুল আচরণ)।
  final String id;
  final String songId;
  final String title;
  final String author;
  final String thumbnail;
  final DateTime playedAt;
  final bool completed;
  final bool skipped;
  final Duration? playedDuration;

  const HistoryLogEntry({
    required this.id,
    required this.songId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.playedAt,
    required this.completed,
    required this.skipped,
    this.playedDuration,
  });

  /// তিনটা outcome-এর একটা human-readable label — HistoryEntries.skipped
  /// (Phase 0.9 fix)-এর ব্যাখ্যা অনুযায়ী: completed=true → শেষ পর্যন্ত
  /// শোনা; skipped=true → ইচ্ছাকৃত skip; দুটোই false → network/error
  /// interruption (কোনো user-intent signal না, তাই এটাকে "interrupted"
  /// হিসেবে দেখানো হচ্ছে, silently ignore করা হচ্ছে না — user history-তে
  /// পুরোপুরি বাদ দিলে বিভ্রান্তিকর হতো, গানটা তো play হয়েছিল)।
  String get outcomeLabel {
    if (completed) return 'সম্পূর্ণ শোনা হয়েছে';
    if (skipped) return 'বাদ দেওয়া হয়েছে';
    return 'থেমে গিয়েছিল';
  }
}

/// একটা distinct "Recently Played" entry — একই গান একাধিকবার শোনা
/// হয়ে থাকলেও একবারই দেখানো হয় (সর্বশেষ play-timestamp অনুযায়ী)।
///
/// Roadmap-এর Phase 1 note অনুযায়ী: এই thumbnail-সহ track-level view-ই
/// আসল "Recently Played" (Spotify-style), যেটা query-based Search
/// History চিপ থেকে architecturally আলাদা।
///
/// ⚠️ Session-lifecycle পুনর্গঠনের পর: এই entry-র ভিত্তি হলো
/// HistoryEntries row-এর *অস্তিত্ব* (playedAt), completed/skipped
/// অবস্থা নয় — BehaviourTrackingService.startPlaybackSession() playback
/// থ্রেশহোল্ড (৩-৫s) পার হলেই row তৈরি করে দেয়, তাই এই entry গান
/// শেষ/skip হওয়ার আগেই দেখা যায় (Spotify-সুলভ, delayed না)।
class RecentlyPlayedEntry {
  final String songId;
  final String title;
  final String author;
  final String thumbnail;
  final DateTime lastPlayedAt;

  const RecentlyPlayedEntry({
    required this.songId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.lastPlayedAt,
  });
}

/// একটা গানের derived Behaviour Tracking summary —
/// LibraryRepository.getBehaviourStats() রিটার্ন করে।
///
/// ⚠️ এই সব সংখ্যা কোনো নতুন column/insert থেকে আসে না — HistoryEntries-এর
/// existing `completed`/`skipped`/`playedDurationMs` column থেকে
/// query-time-এ derive হয় (থ্রেশহোল্ড rule প্রয়োগ করে: Play Count =
/// playedDuration >= max(30s, 50% of track duration), Complete Count =
/// completed flag, Skip Count = skipped flag)। Recently Played-এর
/// row-count থেকে এই সংখ্যাগুলো ভিন্ন হতে পারে — একটা গান "recently
/// played"-এ থাকতে পারে (৩-৫s পার হয়েছে) কিন্তু Play Count-এ না গোনা
/// হতে পারে (৩০s/৫০% threshold পার হয়নি), এটাই ইচ্ছাকৃত।
class BehaviourStats {
  final String songId;
  final int playCount;
  final int skipCount;
  final int completeCount;
  final Duration totalListenDuration;

  const BehaviourStats({
    required this.songId,
    required this.playCount,
    required this.skipCount,
    required this.completeCount,
    required this.totalListenDuration,
  });
}

/// একটা locally cached (downloaded) গান — Library-র "Downloaded Songs"
/// section-এ দেখানোর জন্য, thumbnail + cache size সহ।
///
/// ⚠️ এটা `CacheRepository.getAllCachedSongs()`-এর raw
/// `({videoId, cachePath, sizeBytes})` tuple থেকে ইচ্ছাকৃতভাবে আলাদা —
/// সেই tuple শুধু filesystem-reconciliation-এর জন্য (CacheService
/// internal), এই model UI-facing (title/author/thumbnail-সহ,
/// cachePath ছাড়া — UI-র cachePath জানার দরকার নেই)। RecentlyPlayedEntry/
/// FavoriteSong-এর একই নীতি: raw Drift/tuple শেপ UI-তে সরাসরি এক্সপোজ
/// না করে UI-friendly model বানানো।
class CachedSongEntry {
  final String songId;
  final String title;
  final String author;
  final String thumbnail;
  final int cacheSizeBytes;

  const CachedSongEntry({
    required this.songId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.cacheSizeBytes,
  });

  /// UI-তে "12.4 MB" স্টাইলে দেখানোর জন্য — bytes থেকে human-readable।
  String get formattedSize {
    final mb = cacheSizeBytes / (1024 * 1024);
    if (mb < 1) {
      final kb = cacheSizeBytes / 1024;
      return '${kb.toStringAsFixed(0)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}