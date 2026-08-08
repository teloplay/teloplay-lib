import 'package:drift/drift.dart';
import 'songs_table.dart';

@TableIndex(name: 'idx_queue_user', columns: {#userId})
class QueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Supabase auth.uid() — কার queue eta বোঝার জন্য
  TextColumn get userId => text()();

  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();

  /// Drag & drop reorder-এর জন্য
  IntColumn get position => integer()();

  /// এখন কোনটা বাজছে সেটা track করার জন্য
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();

  // ⚠️ Phase 0.9 (Foundation Hardening) — Resume Position foundation।
  //
  // এটা Phase 1-এর নিজস্ব committed scope-এরই ("Resume playback position")
  // underlying schema — আগে এই column না থাকায় elapsed/seek-time কোথাও
  // persist হচ্ছিল না, শুধু queue-এর ভেতরের index (position) ছিল। এই
  // column এখন যোগ করায় Phase 1-এ resume-position feature লেখার সময়
  // এবং Phase 4-এ cross-device sync ("Playback Position") করার সময়
  // কোনো নতুন migration লাগবে না।

  /// current track-এ শেষ জানা playback position (milliseconds)।
  /// isCurrent=true row-এর জন্যই মূলত অর্থবহ, কিন্তু সব row-এ রাখা হলো
  /// (যদি ভবিষ্যতে per-track resume দরকার হয়, যেমন queue-তে আগের কোনো
  /// track আবার বাজানো হলে সেই track যেখানে ছাড়া হয়েছিল সেখান থেকেই
  /// শুরু করা)।
  IntColumn get lastPositionMs =>
      integer().nullable().withDefault(const Constant(0))();

  /// Last-Write-Wins cross-device sync-এর জন্য — কোন device সবচেয়ে
  /// সাম্প্রতিক queue update করেছে সেটা বোঝা যাবে (Phase 4/7)
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}