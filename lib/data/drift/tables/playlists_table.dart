import 'package:drift/drift.dart';

class Playlists extends Table {
  TextColumn get id => text()(); // UUID

  /// Supabase auth.uid() — Guest Mode-ও Anonymous Auth ব্যবহার করে,
  /// তাই সবসময় real uid থাকে, null হয় না
  TextColumn get userId => text()();

  TextColumn get name => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}