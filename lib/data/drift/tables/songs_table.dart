import 'package:drift/drift.dart';

/// শুধু user-related গান (favorite/history/queue/playlist/cache করা গান)।
/// পুরো YouTube search catalog এখানে persist হবে না।
class Songs extends Table {
  /// YouTube videoId কে PK হিসেবে ব্যবহার করা হচ্ছে
  TextColumn get id => text()();

  TextColumn get title => text()();
  TextColumn get author => text()();
  TextColumn get thumbnail => text()();

  IntColumn get durationSeconds => integer().nullable()();

  // ⚠️ Phase 0.9 (Foundation Hardening) — নতুন nullable metadata columns।
  //
  // এখন কোনো caller এই field populate করছে না (Innertube/yt-dlp search
  // result-এ structured genre/artist-ID থাকে না) — কিন্তু column এখনই
  // থাকা জরুরি কারণ Recommendation Engine ও Smart Queue (Phase 7+) এই
  // মেটাডেটার উপর নির্ভর করবে। Column না থাকলে তখন migration + production
  // data backfill লাগত (backfill প্রায় অসম্ভব, কারণ পুরনো data থেকে genre
  // retroactively বের করা যায় না)। এখন nullable রাখায় কোনো migration
  // ছাড়াই ভবিষ্যতে যখন data source থেকে এই তথ্য পাওয়া সম্ভব হবে তখন
  // populate করা যাবে।

  /// Recommendation/Smart Queue-এর জন্য genre/category signal।
  /// এখনো কোনো caller populate করছে না — future data source integration
  /// এর অপেক্ষায়।
  TextColumn get genre => text().nullable()();

  /// Normalized artist identifier — বর্তমান `author` free-text field-এর
  /// বিকল্প/সম্পূরক। ভবিষ্যতে আলাদা normalized Artists table-এ migrate
  /// করার সেতু হিসেবে রাখা, এখন শুধু placeholder string ID (যদি data
  /// source থেকে পাওয়া যায়)।
  TextColumn get artistId => text().nullable()();

  // ⚠️ Phase 6.5B (Song/Album Details) — নতুন nullable metadata columns!
  //
  // Locked decision: Albums এখনো আলাদা table না (দেখো Phase_6.5B_Roadmap.md
  // ধাপ ৮ — "future: Proper Albums table")। এই দুইটো flat column Songs
  // টেবিলেই রাখা হচ্ছে, ঠিক genre/artistId-এর মতোই pattern — নতুন কোনো
  // caller এখনই populate করছে না, কিন্তু Album Details Screen (পরের ধাপ)
  // এবং SongDetailsScreen-এর "Go to Album" button এই কলাম দুটোর উপর
  // নির্ভর করবে। Genre/artistId-এর একই যুক্তি প্রযোজ্য এখানেও: column
  // এখনই না থাকলে পরে migration + backfill লাগত, backfill প্রায়
  // অসম্ভব (পুরোনো data থেকে album retroactively বের করা যায় না)।

  /// এই গান কোন album-এর অংশ — normalized album identifier। এখনো কোনো
  /// caller populate করছে না, Album Details Screen implement হওয়ার পর
  /// data source integration সাপেক্ষে ভরাট হবে।
  TextColumn get albumId => text().nullable()();

  /// Album-এর display নাম — `albumId` নাল হলেও থাকতে পারে (কিছু data
  /// source শুধু album title দেয়, structured ID না), তাই দুটো আলাদা
  /// nullable column, একটার উপর আরেকটা নির্ভরশীল নয়।
  TextColumn get albumName => text().nullable()();

  /// কোন backend/engine থেকে এই গানের data এসেছে (যেমন
  /// 'innertube/windows', 'innertube/android', 'yt-dlp/windows') —
  /// debug/troubleshooting-এর জন্য, cross-platform videoId mismatch-জাতীয়
  /// সমস্যা তদন্তে সাহায্য করবে।
  TextColumn get platformSource => text().nullable()();

  /// Phase 3 (Smart Cache)-এ ব্যবহার হবে
  BoolColumn get cachedLocally =>
      boolean().withDefault(const Constant(false))();
  TextColumn get cachePath => text().nullable()();
  IntColumn get cacheSizeBytes => integer().nullable()();

  // ⚠️ Phase 3 Item D (Cache Health/Diagnostics) — নতুন nullable column।
  //
  // SHA-256 checksum, cache_service.dart-এর verifyCacheIntegrity()/
  // verifySingleTrack()-এর জন্য। platformSource-এর মতোই pattern:
  // nullable, কোনো default নেই। Lazy-populate — প্রথমবার full verify
  // চালানোর সময় checksum না থাকলে persist করা হয়, পরের বার real
  // compare-এ ব্যবহার হয়। markCached()/clearCacheFlag()-এ এই field
  // reset হয় (cache_repository.dart দেখো)।
  TextColumn get cacheChecksum => text().nullable()();

  DateTimeColumn get addedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}