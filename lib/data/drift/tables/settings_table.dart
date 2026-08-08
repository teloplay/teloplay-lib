import 'package:drift/drift.dart';

/// App settings (theme, quality, language) — simple key-value table।
/// নতুন setting যোগ করতে schema migration লাগবে না, শুধু key ব্যবহার করলেই হবে।
class SettingsEntries extends Table {
  /// Supabase auth.uid() — একই device-এ একাধিক account থাকলে
  /// প্রতিটার settings আলাদা থাকবে
  TextColumn get userId => text()();

  TextColumn get key => text()();

  /// জটিল value হলে JSON string হিসেবে store করা হবে
  TextColumn get value => text()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {userId, key};
}