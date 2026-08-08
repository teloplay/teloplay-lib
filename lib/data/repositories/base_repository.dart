import '../drift/database.dart';

/// সব Repository-এর base class।
///
/// নিয়ম (roadmap অনুযায়ী):
/// - UI কখনো সরাসরি Drift/Supabase টাচ করবে না, সবসময় Repository দিয়ে যাবে
/// - Repository-ই একমাত্র জায়গা যেখানে data source (local/remote) নিয়ে সিদ্ধান্ত হয়
/// - প্রতিটা write operation স্থানীয়ভাবে Drift-এ সাথে সাথে হবে (UI instant update),
///   তারপর SyncQueue-এ entry যোগ হবে ব্যাকগ্রাউন্ড sync-এর জন্য
abstract class BaseRepository {
  final AppDatabase db;

  BaseRepository(this.db);
}