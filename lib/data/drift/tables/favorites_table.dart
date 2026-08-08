import 'package:drift/drift.dart';
import 'songs_table.dart';

class Favorites extends Table {
  /// Supabase auth.uid() — guest (anonymous) অবস্থাতেও real uid থাকে
  TextColumn get userId => text()();

  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();

  /// "Recently Liked" feature-এর জন্য
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {userId, songId};
}