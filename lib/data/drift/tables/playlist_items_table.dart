import 'package:drift/drift.dart';
import 'playlists_table.dart';
import 'songs_table.dart';

class PlaylistItems extends Table {
  TextColumn get id => text()(); // UUID

  TextColumn get playlistId =>
      text().references(Playlists, #id, onDelete: KeyAction.cascade)();

  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();

  /// Ordering / drag & drop reorder-এর জন্য
  IntColumn get position => integer()();

  DateTimeColumn get addedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}