import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../drift/database.dart';

/// একটা recent-search entry — UI-তে দেখানোর জন্য প্রয়োজনীয় ন্যূনতম shape।
/// পুরো `SearchHistoryEntry` (Drift-generated row) না এক্সপোজ করে ছোট,
/// UI-friendly model রাখা হয়েছে — future Phase 2 (Most Searched) এ
/// resultCount/searchedAt দরকার হলে এখানে যোগ করা যাবে, breaking change
/// ছাড়াই।
class RecentSearch {
  final String query;
  final DateTime searchedAt;

  const RecentSearch({required this.query, required this.searchedAt});
}

/// `SearchHistoryEntries` টেবিলের উপর read-only query wrapper।
///
/// ⚠️ Phase 1 (Smart Search UI) — এই repository শুধু recent-searches
/// পড়ে (Phase 1 scope: "Recent searches" UI)। Most Searched/aggregation
/// query (Phase 2 scope) এখানে যোগ হবে না — সেটা আলাদা মেথড হিসেবে
/// Phase 2-তে আসবে, single-responsibility বজায় রাখতে (এই repository
/// শুধু "recent" ধারণার জন্য দায়ী)।
///
/// লেখা (insert) এখনো `BehaviourTrackingService`-এই থাকছে (Phase 0.9
/// সিদ্ধান্ত অনুযায়ী — search capture-এর single entry point)। এই
/// repository ইচ্ছাকৃতভাবে write করে না, শুধু পড়ে — যাতে দুই জায়গা
/// থেকে একই টেবিলে insert-logic ছড়িয়ে না যায়।
class SearchHistoryRepository {
  final AppDatabase _db;

  SearchHistoryRepository(this._db);

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  /// সাম্প্রতিক, distinct search query-গুলো — নতুন থেকে পুরনো ক্রমে।
  ///
  /// একই query একাধিকবার search করা হলে শুধু সবচেয়ে সাম্প্রতিকটাই
  /// দেখানো হয় (duplicate chip এড়াতে) — `GROUP BY query` দিয়ে
  /// প্রতিটা distinct query-র সর্বোচ্চ `searchedAt` বের করে, তারপর
  /// সেই timestamp অনুযায়ী descending sort।
  Future<List<RecentSearch>> getRecentSearches({int limit = 10}) async {
    final userId = _userId;
    if (userId == null) return [];

    final table = _db.searchHistoryEntries;
    final maxSearchedAt = table.searchedAt.max();

    final query = _db.selectOnly(table)
      ..addColumns([table.query, maxSearchedAt])
      ..where(table.userId.equals(userId))
      ..groupBy([table.query])
      ..orderBy([OrderingTerm.desc(maxSearchedAt)])
      ..limit(limit);

    final rows = await query.get();

    return rows.map((row) {
      return RecentSearch(
        query: row.read(table.query)!,
        searchedAt: row.read(maxSearchedAt)!,
      );
    }).toList();
  }

  /// একটা নির্দিষ্ট recent-search entry মুছে ফেলা (chip-এ "x" চাপলে) —
  /// একই query-র সব পুরনো row মুছে দেয় (user শুধু "এই query-টা আর
  /// recent-এ দেখতে চাই না" বোঝাতে চাইলে সবগুলো instance সরানোই সঠিক)।
  Future<void> removeSearch(String query) async {
    final userId = _userId;
    if (userId == null) return;

    await (_db.delete(_db.searchHistoryEntries)
          ..where((t) => t.userId.equals(userId) & t.query.equals(query)))
        .go();
  }
}