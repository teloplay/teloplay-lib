import 'package:drift/drift.dart';
import 'songs_table.dart';

@TableIndex(name: 'idx_history_user', columns: {#userId})
// Behaviour Tracking (Phase 2) ও Statistics (Phase 7+, Most Played,
// Listening Statistics) query গুলো প্রায় সবসময় "কোন গান কতবার/কতক্ষণ
// শোনা হয়েছে" জাতীয় aggregation করবে, যেখানে songId ভিত্তিক GROUP BY
// দরকার হবে — শুধু userId index থাকলে এই query গুলো ধীরে চলত। এই
// composite index migration ছাড়াই যোগ করা হয়েছিল (v6)।
@TableIndex(name: 'idx_history_songId', columns: {#userId, #songId})
class HistoryEntries extends Table {
  TextColumn get id => text()(); // UUID

  /// Supabase auth.uid()
  TextColumn get userId => text()();

  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get playedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// কতক্ষণ শোনা হয়েছে (ভবিষ্যৎ Stats ফিচারের জন্য)
  IntColumn get playedDurationMs => integer().nullable()();

  /// user গানটা শেষ পর্যন্ত শুনেছে কিনা — future recommendation
  /// engine-এ কাজে লাগবে।
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  // ⚠️ Phase 0.9 (Foundation Hardening) — completed/skipped ambiguity fix।
  //
  // আগে শুধু `completed: bool` থাকায় তিনটা ভিন্ন পরিস্থিতি আলাদা করা
  // যাচ্ছিল না: (ক) গান শেষ পর্যন্ত শোনা হয়েছে, (খ) user ইচ্ছাকৃতভাবে
  // skip করেছে, (গ) network/error-এ playback থেমে গেছে। এই তিনটা
  // signal-এর মান সম্পূর্ণ ভিন্ন Recommendation Engine (Phase 7+)-এর
  // জন্য — "skip" মানে user পছন্দ করেনি (নেতিবাচক signal), কিন্তু
  // "error interruption" কোনো signal-ই না। পুরনো data থেকে retroactively
  // এই পার্থক্য বের করা অসম্ভব, তাই schema fix এখনই করা হলো Behaviour
  // Tracking capture শুরুর আগেই (Phase 1/2)।
  //
  // ব্যাখ্যা: completed=true → শেষ পর্যন্ত শোনা হয়েছে (skipped সবসময়
  // false/null থাকবে এই ক্ষেত্রে)। completed=false, skipped=true →
  // user ইচ্ছাকৃত skip করেছে। completed=false, skipped=false/null →
  // network/error-এ interruption, কোনো user-intent signal না।
  BoolColumn get skipped => boolean().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}