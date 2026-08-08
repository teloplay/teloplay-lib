import 'package:drift/drift.dart';

/// Search History — Phase 0.9-এ schema তৈরি (Foundation Hardening),
/// Phase 1-এ capture শুরু (recent searches), Phase 2-এ পূর্ণাঙ্গ UI
/// (most searched, suggestions)।
///
/// এই টেবিল আগে থেকে না থাকলে Phase 1-এর "recent searches" ফিচার
/// ভুল জায়গায় (in-memory list বা SettingsEntries key-value hack) বসে
/// যেত, যেটা Phase 2-এ migrate করতে হতো। এখন প্রথমবারেই সঠিক জায়গা।
@TableIndex(name: 'idx_search_history_user', columns: {#userId})
// "Most Searched" aggregation (Phase 2)-এর জন্য — একই user একই query
// কতবার করেছে সেটা efficiently count করতে composite index।
@TableIndex(name: 'idx_search_history_query', columns: {#userId, #query})
class SearchHistoryEntries extends Table {
  TextColumn get id => text()(); // UUID

  /// Supabase auth.uid()
  TextColumn get userId => text()();

  /// ব্যবহারকারীর টাইপ করা search query, verbatim (case যেমন টাইপ করা
  /// হয়েছিল তেমনই রাখা হচ্ছে — "most searched" aggregation-এর সময়
  /// case-insensitive grouping করতে চাইলে query-level এ LOWER() করা
  /// যাবে, এখানে normalize করে data হারানোর দরকার নেই)
  TextColumn get query => text()();

  DateTimeColumn get searchedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// এই search কতগুলো ফলাফল দিয়েছিল — zero-result query চিহ্নিত করতে
  /// কাজে লাগবে (ভবিষ্যতে "no results for X" pattern খুঁজে content-gap
  /// বোঝার জন্য), এখনই এই aggregation ব্যবহার হচ্ছে না।
  IntColumn get resultCount => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}